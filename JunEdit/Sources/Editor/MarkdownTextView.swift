import Cocoa

class MarkdownTextView: NSTextView {

    // Support drag-and-drop of images
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasteboard = sender.draggingPasteboard.propertyList(forType: .fileURL) as? String,
              let fileURL = URL(string: pasteboard) else {
            return super.performDragOperation(sender)
        }

        let ext = fileURL.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(ext) else {
            return super.performDragOperation(sender)
        }

        // Copy image to post's assets directory
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

            // Insert markdown image reference at cursor
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
