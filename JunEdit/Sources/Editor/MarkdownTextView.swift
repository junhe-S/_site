import Cocoa

struct CodeBlockInfo {
    let range: NSRange       // full range including fences
    let language: String     // e.g. "python", "python {hide}"
    let bodyRange: NSRange   // range of code content (between fences)
}

struct BlockquoteInfo {
    let range: NSRange         // combined range of all consecutive > lines
    let isCallout: Bool        // starts with > [!type]
    let calloutType: String    // "note", "warning", etc.
}

class MarkdownTextView: NSTextView {

    // Code block regions (set by EditorViewController during highlighting)
    var codeBlocks: [CodeBlockInfo] = []

    // Blockquote regions
    var blockquotes: [BlockquoteInfo] = []

    // Theme colors (set by EditorViewController)
    var codeBlockBackground: NSColor = .controlBackgroundColor
    var codeBlockBorder: NSColor = .separatorColor
    var langLabelColor: NSColor = .secondaryLabelColor
    var langLabelFont: NSFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    var langPillBg: NSColor = .separatorColor

    // Blockquote colors
    var quoteBg: NSColor = .controlBackgroundColor
    var quoteBorder: NSColor = .systemBlue

    // MARK: - Custom drawing for backgrounds

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        for block in codeBlocks {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            let blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let inset = textContainerInset
            let drawRect = NSRect(
                x: inset.width + 4,
                y: blockRect.origin.y + inset.height - 4,
                width: bounds.width - inset.width * 2 - 8,
                height: blockRect.height + 8
            )

            // Rounded rect background
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 8, yRadius: 8)
            codeBlockBackground.setFill()
            path.fill()

            // Subtle border
            codeBlockBorder.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()

            // Language pill badge (top-right, like Typora)
            let displayLang = block.language
                .replacingOccurrences(of: #"\s*\{(show|hide)\}"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if !displayLang.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: langLabelFont,
                    .foregroundColor: langLabelColor,
                ]
                let labelStr = NSAttributedString(string: displayLang, attributes: attrs)
                let labelSize = labelStr.size()

                // Pill background
                let pillPadH: CGFloat = 8
                let pillPadV: CGFloat = 2
                let pillRect = NSRect(
                    x: drawRect.maxX - labelSize.width - pillPadH * 2 - 8,
                    y: drawRect.minY + 6,
                    width: labelSize.width + pillPadH * 2,
                    height: labelSize.height + pillPadV * 2
                )
                let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
                langPillBg.setFill()
                pillPath.fill()

                // Label text centered in pill
                let labelPoint = NSPoint(
                    x: pillRect.origin.x + pillPadH,
                    y: pillRect.origin.y + pillPadV
                )
                labelStr.draw(at: labelPoint)
            }
        }

        // Draw blockquote backgrounds
        for quote in blockquotes {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: quote.range, actualCharacterRange: nil)
            let blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let inset = textContainerInset
            let drawRect = NSRect(
                x: inset.width + 4,
                y: blockRect.origin.y + inset.height - 3,
                width: bounds.width - inset.width * 2 - 8,
                height: blockRect.height + 6
            )

            // Rounded background
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 8, yRadius: 8)
            quoteBg.setFill()
            path.fill()

            // Left accent border (4px, like Mdmdt)
            let borderRect = NSRect(
                x: drawRect.origin.x,
                y: drawRect.origin.y,
                width: 4,
                height: drawRect.height
            )
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 2, yRadius: 2)
            quoteBorder.setFill()
            borderPath.fill()
        }
    }

    // MARK: - Drag and drop images

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasteboard = sender.draggingPasteboard.propertyList(forType: .fileURL) as? String,
              let fileURL = URL(string: pasteboard) else {
            return super.performDragOperation(sender)
        }

        let ext = fileURL.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(ext) else {
            return super.performDragOperation(sender)
        }

        guard let editorVC = (self.delegate as? EditorViewController),
              let post = editorVC.currentPost else {
            return super.performDragOperation(sender)
        }

        let assetsDir = post.path.deletingLastPathComponent().appendingPathComponent("assets")
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let destURL = assetsDir.appendingPathComponent(fileURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: destURL)

            let mdImage = "![](assets/\(fileURL.lastPathComponent))"
            insertText(mdImage, replacementRange: selectedRange())
            return true
        } catch {
            return super.performDragOperation(sender)
        }
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .string]
    }

    // Tab key inserts spaces
    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange())
    }
}
