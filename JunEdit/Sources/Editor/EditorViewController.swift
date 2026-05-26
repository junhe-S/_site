import Cocoa
import WebKit

class EditorViewController: NSViewController, NSTextViewDelegate {
    private let editorScroll = NSScrollView()
    private let textView = MarkdownTextView()
    private let previewView = WKWebView()
    private let previewScroll = NSView() // container
    private let innerSplit = NSSplitView()
    private var isPreviewVisible = false

    private var saveTimer: Timer?
    private var isDirty = false

    var currentPost: BlogPost?
    var onContentChanged: ((String) -> Void)?

    // MARK: - Lifecycle

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        v.wantsLayer = true
        view = v

        setupInnerSplitView()
    }

    private func setupInnerSplitView() {
        // The inner split holds: editor | preview side-by-side
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(innerSplit)

        NSLayoutConstraint.activate([
            innerSplit.topAnchor.constraint(equalTo: view.topAnchor),
            innerSplit.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            innerSplit.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            innerSplit.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Editor side
        setupEditor()
        innerSplit.addSubview(editorScroll)

        // Preview side (hidden by default)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        innerSplit.addSubview(previewView)

        // Start with preview hidden
        previewView.isHidden = true

        showPlaceholder()
    }

    private func setupEditor() {
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Proportional serif font like MiaoYan
        let serif = NSFont(name: "Georgia", size: 15) ?? NSFont.systemFont(ofSize: 15)
        textView.font = serif
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.labelColor
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 36, height: 24)

        // Generous line spacing
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 6
        ps.paragraphSpacing = 4
        textView.defaultParagraphStyle = ps

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        editorScroll.documentView = textView
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.drawsBackground = false

        // Scroll sync
        editorScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(editorDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: editorScroll.contentView
        )
    }

    // MARK: - Preview toggle (splits editor pane)

    func togglePreview() {
        isPreviewVisible.toggle()
        previewView.isHidden = !isPreviewVisible

        if isPreviewVisible {
            // Force equal split
            let totalWidth = innerSplit.bounds.width
            let half = totalWidth / 2
            innerSplit.setPosition(half, ofDividerAt: 0)
            updatePreviewContent()
        }
    }

    // MARK: - Scroll sync

    @objc private func editorDidScroll() {
        guard isPreviewVisible, let docView = editorScroll.documentView else { return }
        let visibleRect = editorScroll.contentView.bounds
        let totalHeight = docView.frame.height - editorScroll.contentView.bounds.height
        guard totalHeight > 0 else { return }
        let progress = min(max(visibleRect.origin.y / totalHeight, 0), 1)
        let js = "window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * \(progress));"
        previewView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Load / Save

    private func showPlaceholder() {
        textView.string = "Select a post from the sidebar, or create a new one (⌘N)\n\nSet your blog directory: File → Set Blog Directory (⌘,)"
        textView.textColor = NSColor.secondaryLabelColor
        textView.isEditable = false
    }

    func loadPost(_ post: BlogPost) {
        if isDirty { save() }
        currentPost = post

        guard let content = try? String(contentsOf: post.path, encoding: .utf8) else { return }

        textView.isEditable = true
        textView.textColor = NSColor.labelColor
        textView.string = content
        isDirty = false

        highlightMarkdown()
        if isPreviewVisible { updatePreviewContent() }
    }

    func save() {
        guard let post = currentPost, isDirty else { return }
        do {
            try textView.string.write(to: post.path, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        isDirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.highlightMarkdown()
            if self?.isPreviewVisible == true { self?.updatePreviewContent() }
        }
    }

    // MARK: - Context menu

    func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
        menu.addItem(.separator())

        for (title, sel) in [
            ("Bold", #selector(insertBold)),
            ("Italic", #selector(insertItalic)),
            ("Code", #selector(insertInlineCode)),
            ("Link", #selector(insertLink)),
        ] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let cb = NSMenuItem(title: "Code Block {show}", action: #selector(insertCodeBlock), keyEquivalent: "")
        cb.target = self
        menu.addItem(cb)

        let img = NSMenuItem(title: "Image", action: #selector(insertImage), keyEquivalent: "")
        img.target = self
        menu.addItem(img)

        return menu
    }

    @objc private func insertBold() { wrapSelection(prefix: "**", suffix: "**", placeholder: "bold") }
    @objc private func insertItalic() { wrapSelection(prefix: "*", suffix: "*", placeholder: "italic") }
    @objc private func insertInlineCode() { wrapSelection(prefix: "`", suffix: "`", placeholder: "code") }

    @objc private func insertLink() {
        let sel = (textView.string as NSString).substring(with: textView.selectedRange())
        let text = sel.isEmpty ? "link text" : sel
        textView.insertText("[\(text)](url)", replacementRange: textView.selectedRange())
    }

    @objc private func insertCodeBlock() {
        textView.insertText("```python {show}\n# code\n```", replacementRange: textView.selectedRange())
    }

    @objc private func insertImage() {
        textView.insertText("![](assets/image.png)", replacementRange: textView.selectedRange())
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let range = textView.selectedRange()
        let sel = (textView.string as NSString).substring(with: range)
        textView.insertText("\(prefix)\(sel.isEmpty ? placeholder : sel)\(suffix)", replacementRange: range)
    }

    // MARK: - Preview HTML

    private func updatePreviewContent() {
        let html = buildPreviewHTML(textView.string)
        let baseURL = BlogSettings.shared.blogDirectory
        previewView.loadHTMLString(html, baseURL: baseURL)
    }

    private func buildPreviewHTML(_ raw: String) -> String {
        var body = raw
        var title = ""
        var date = ""

        if raw.hasPrefix("---") {
            let parts = raw.components(separatedBy: "---")
            if parts.count >= 3 {
                let yaml = parts[1]
                body = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
                for line in yaml.components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("title:") {
                        title = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if title.hasPrefix("\"") && title.hasSuffix("\"") { title = String(title.dropFirst().dropLast()) }
                    } else if t.hasPrefix("date:") {
                        date = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>\(previewCSS())</style></head><body><article>
        \(title.isEmpty ? "" : "<h1>\(esc(title))</h1>")
        \(date.isEmpty ? "" : "<div class=\"meta\">\(esc(date))</div>")
        \(convertMD(body))
        </article></body></html>
        """
    }

    private func convertMD(_ md: String) -> String {
        var html = ""
        var inCode = false
        var codeBuf = ""
        var codeLang = ""

        for line in md.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    html += "<pre><code>\(esc(codeBuf))</code></pre>\n"
                    codeBuf = ""; inCode = false
                } else {
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if let r = codeLang.range(of: #"\s*\{(show|hide)\}"#, options: .regularExpression) {
                        codeLang = String(codeLang[..<r.lowerBound])
                    }
                }
                continue
            }
            if inCode { codeBuf += line + "\n"; continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = String(trimmed.dropFirst(level + 1))
                html += "<h\(level)>\(inlineMD(text))</h\(level)>\n"
            } else if trimmed.hasPrefix("#") {
                html += "<h1>\(inlineMD(String(trimmed.dropFirst(2))))</h1>\n"
            } else if trimmed.hasPrefix(">") {
                let c = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                html += "<blockquote><p>\(inlineMD(c))</p></blockquote>\n"
            } else if trimmed.hasPrefix("![") {
                if let ae = trimmed.range(of: "]("), let ue = trimmed.range(of: ")", range: ae.upperBound..<trimmed.endIndex) {
                    let url = String(trimmed[ae.upperBound..<ue.lowerBound])
                    html += "<div class=\"img\"><img src=\"\(url)\"></div>\n"
                }
            } else if trimmed.isEmpty {
                html += "\n"
            } else {
                html += "<p>\(inlineMD(trimmed))</p>\n"
            }
        }
        return html
    }

    private func inlineMD(_ t: String) -> String {
        var r = esc(t)
        r = r.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\[([^\]]+)\]\(([^\)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return r
    }

    private func esc(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func previewCSS() -> String {
        """
        :root { color-scheme: light dark; }
        body { font-family: Georgia, 'Times New Roman', serif; max-width: 680px; margin: 0 auto;
               padding: 24px 20px; line-height: 1.8; color: #e5e5e5; background: #1a1a1a; }
        @media (prefers-color-scheme: light) {
            body { color: #1a1a1a; background: #fff; }
            code { background: #f0f0f0; } pre { background: #f5f5f5; border-color: #e5e5e5; }
        }
        h1 { font-size: 1.4rem; margin-top: 0; } h2 { font-size: 1.2rem; margin-top: 2rem; }
        p { font-size: 15px; } .meta { color: #888; font-size: 13px; margin-bottom: 1.5rem; }
        code { font-family: ui-monospace, monospace; font-size: 0.85em; background: #2a2a2a;
               padding: 2px 5px; border-radius: 3px; }
        pre { background: #1e1e1e; padding: 14px; border-radius: 6px; overflow-x: auto; border: 1px solid #333; }
        pre code { background: none; padding: 0; }
        a { color: #60a5fa; text-decoration: none; } blockquote { border-left: 3px solid #444;
            margin-left: 0; padding-left: 16px; color: #999; }
        .img { margin: 1.5rem 0; } .img img { max-width: 100%; border-radius: 6px; }
        """
    }

    // MARK: - Syntax Highlighting (subtle, muted colors)

    private func highlightMarkdown() {
        let text = textView.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        guard let storage = textView.textStorage else { return }

        storage.beginEditing()

        let serif = NSFont(name: "Georgia", size: 15) ?? NSFont.systemFont(ofSize: 15)
        storage.addAttribute(.font, value: serif, range: fullRange)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 6
        ps.paragraphSpacing = 4
        storage.addAttribute(.paragraphStyle, value: ps, range: fullRange)

        let nsText = text as NSString

        // Frontmatter — dim gray
        enumeratePattern(#"\A---\n[\s\S]*?\n---"#, in: nsText) { range in
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: range)
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.addAttribute(.font, value: mono, range: range)
        }

        // Headings — slightly larger, medium weight, subtle blue
        enumeratePattern(#"^#{1,6}\s+.+$"#, in: nsText) { range in
            let headingColor = NSColor.labelColor.withAlphaComponent(0.85)
            storage.addAttribute(.foregroundColor, value: headingColor, range: range)
            let bold = NSFont(name: "Georgia-Bold", size: 17) ?? NSFont.boldSystemFont(ofSize: 17)
            storage.addAttribute(.font, value: bold, range: range)
        }

        // Bold
        enumeratePattern(#"\*\*(.+?)\*\*"#, in: nsText) { range in
            let bold = NSFont(name: "Georgia-Bold", size: 15) ?? NSFont.boldSystemFont(ofSize: 15)
            storage.addAttribute(.font, value: bold, range: range)
        }

        // Code blocks — monospace, subtle gray bg hint
        enumeratePattern(#"```[\s\S]*?```"#, in: nsText) { range in
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.addAttribute(.font, value: mono, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }

        // Inline code — monospace, subtle
        enumeratePattern(#"`[^`\n]+`"#, in: nsText) { range in
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.addAttribute(.font, value: mono, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }

        // Links — subtle blue
        enumeratePattern(#"\[([^\]]+)\]\([^\)]+\)"#, in: nsText) { range in
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue.withAlphaComponent(0.7), range: range)
        }

        // Images — subtle purple
        enumeratePattern(#"!\[([^\]]*)\]\([^\)]+\)"#, in: nsText) { range in
            storage.addAttribute(.foregroundColor, value: NSColor.systemPurple.withAlphaComponent(0.6), range: range)
        }

        // Blockquotes — muted
        enumeratePattern(#"^>\s+.+$"#, in: nsText) { range in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        }

        storage.endEditing()
    }

    private func enumeratePattern(_ pattern: String, in text: NSString, handler: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        for result in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            handler(result.range)
        }
    }
}
