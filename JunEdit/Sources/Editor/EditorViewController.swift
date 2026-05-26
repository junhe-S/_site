import Cocoa

class EditorViewController: NSViewController, NSTextViewDelegate {
    private let editorScroll = NSScrollView()
    private let textView = MarkdownTextView()

    private var saveTimer: Timer?
    private var isDirty = false
    private var activeLine: Int = -1
    private var isHighlighting = false

    var currentPost: BlogPost?
    var onContentChanged: ((String) -> Void)?

    // MARK: - Mdmdt Theme Fonts (exact values from mdmdt-dark.css)

    private let bodyFont: NSFont = {
        return NSFont(name: "PingFang SC", size: 16) ?? NSFont.systemFont(ofSize: 16)
    }()
    // Bold: font-weight 800, not just semibold
    private let bodyBold: NSFont = {
        return NSFont(name: "PingFang SC", size: 16).flatMap {
            NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask)
        } ?? NSFont.boldSystemFont(ofSize: 16)
    }()
    private let bodyItalic: NSFont = {
        let fd = NSFontDescriptor(name: "PingFang SC", size: 16).withSymbolicTraits(.italic)
        return NSFont(descriptor: fd, size: 16) ?? NSFont.systemFont(ofSize: 16)
    }()
    private let monoFont: NSFont = {
        return NSFont(name: "JetBrains Mono", size: 14)
            ?? NSFont(name: "Source Code Pro", size: 14)
            ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }()
    private let h1Font: NSFont = {
        return NSFont(name: "PingFang SC Semibold", size: 32) ?? NSFont.boldSystemFont(ofSize: 32)
    }()
    private let h2Font: NSFont = {
        return NSFont(name: "PingFang SC Semibold", size: 28) ?? NSFont.boldSystemFont(ofSize: 28)
    }()
    private let h3Font: NSFont = {
        return NSFont(name: "PingFang SC Semibold", size: 24) ?? NSFont.boldSystemFont(ofSize: 24)
    }()
    private let h4Font: NSFont = {
        return NSFont(name: "PingFang SC Semibold", size: 20) ?? NSFont.boldSystemFont(ofSize: 20)
    }()

    // MARK: - Mdmdt Theme Colors (exact from CSS variables)

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    // --bg-color
    private var bgColor: NSColor { isDark ? NSColor(hex: "#1b1b1f") : NSColor(hex: "#fafafc") }
    // --text-color
    private var textColor: NSColor { isDark ? NSColor(hex: "#d0d0d0") : NSColor(hex: "#070909") }
    // --color-1 (blue)
    private var accentBlue: NSColor { NSColor(hex: "#3e69d7") }
    // --color-2 (orange, hover)
    private var accentOrange: NSColor { NSColor(hex: "#f59102") }
    // --text-code
    private var codeTextColor: NSColor { isDark ? NSColor(hex: "#bbc7fd") : NSColor(hex: "#2f479f") }
    // Inline code bg: --color-1-0-a (30% dark, 15% light)
    private var codeBgColor: NSColor { isDark ? NSColor(hex: "#3e69d7").withAlphaComponent(0.3) : NSColor(hex: "#3e69d7").withAlphaComponent(0.15) }
    // Code block bg: --bg-color2
    private var codeBlockBg: NSColor { isDark ? NSColor(hex: "#282a32") : NSColor(hex: "#ececee") }
    // --text-grey
    private var secondaryText: NSColor { isDark ? NSColor(hex: "#464b50") : NSColor(hex: "#666666") }
    // --border-color
    private var borderColor: NSColor { isDark ? NSColor(hex: "#464b50") : NSColor(hex: "#d2d2d2") }
    // Bold text color (dark only)
    private var boldColor: NSColor { isDark ? NSColor(hex: "#cfdfff") : NSColor(hex: "#070909") }
    // Strikethrough color
    private var strikeColor: NSColor { NSColor(hex: "#e30f2e") }

    // MARK: - Lifecycle

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        v.wantsLayer = true
        view = v
        setupEditor()

        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorScroll)
        NSLayoutConstraint.activate([
            editorScroll.topAnchor.constraint(equalTo: view.topAnchor),
            editorScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        showPlaceholder()
    }

    private func setupEditor() {
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.font = bodyFont
        textView.textColor = textColor
        textView.backgroundColor = bgColor
        textView.insertionPointColor = accentBlue
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 36, height: 24)

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 2
        ps.paragraphSpacing = 2
        textView.defaultParagraphStyle = ps
        textView.typingAttributes = [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: ps,
        ]

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        editorScroll.documentView = textView
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.drawsBackground = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        // Re-highlight when system appearance changes
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.highlightMarkdown()
        }
    }

    // MARK: - Load / Save

    private func showPlaceholder() {
        textView.string = "Select a post from the sidebar, or create a new one (⌘N)\n\nSet your blog directory: File → Set Blog Directory (⌘,)"
        textView.textColor = secondaryText
        textView.isEditable = false
    }

    // MARK: - AI Integration APIs

    /// Returns the currently selected text, or nil if no selection
    func selectedText() -> String? {
        let range = textView.selectedRange()
        guard range.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: range)
    }

    /// Returns the full document text
    func documentText() -> String {
        return textView.string
    }

    /// Replaces the current selection with new text
    func replaceSelection(with text: String) {
        let range = textView.selectedRange()
        textView.insertText(text, replacementRange: range)
        isDirty = true
        highlightMarkdown()
        onContentChanged?(textView.string)
    }

    /// Inserts text at the current cursor position
    func insertAtCursor(_ text: String) {
        let loc = textView.selectedRange().location
        let range = NSRange(location: loc, length: 0)
        textView.insertText(text, replacementRange: range)
        isDirty = true
        highlightMarkdown()
        onContentChanged?(textView.string)
    }

    /// Appends text below the current line
    func appendBelowCursor(_ text: String) {
        let nsString = textView.string as NSString
        let cursorLoc = textView.selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLoc, length: 0))
        let insertLoc = lineRange.location + lineRange.length
        let insertion = text.hasPrefix("\n") ? text : "\n" + text
        textView.insertText(insertion, replacementRange: NSRange(location: insertLoc, length: 0))
        isDirty = true
        highlightMarkdown()
        onContentChanged?(textView.string)
    }

    /// Returns the NSView for anchoring popovers
    var editorView: NSView { textView }

    /// Returns the rect of the current selection/cursor for popover positioning
    func cursorRect() -> NSRect {
        let range = textView.selectedRange()
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let inset = textView.textContainerInset
        rect.origin.x += inset.width
        rect.origin.y += inset.height
        return textView.convert(rect, to: view)
    }

    func clearPost() {
        currentPost = nil
        isDirty = false
        showPlaceholder()
    }

    func loadPost(_ post: BlogPost) {
        if isDirty { save() }
        currentPost = post

        guard let content = try? String(contentsOf: post.path, encoding: .utf8) else { return }

        textView.isEditable = true
        textView.textColor = textColor
        textView.string = content
        isDirty = false
        activeLine = -1

        highlightMarkdown()
        onContentChanged?(content)
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
            guard let self = self else { return }
            self.updateActiveLine()
            self.highlightMarkdown()
            self.onContentChanged?(self.textView.string)
        }
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        updateActiveLine()
        highlightMarkdown()
    }

    private func updateActiveLine() {
        let text = textView.string as NSString
        let loc = textView.selectedRange().location
        guard loc <= text.length else { return }

        var line = 0
        var pos = 0
        while pos < loc {
            let nl = text.range(of: "\n", options: [], range: NSRange(location: pos, length: text.length - pos))
            if nl.location == NSNotFound || nl.location >= loc { break }
            pos = nl.location + 1
            line += 1
        }
        activeLine = line
    }

    // MARK: - Typora-style Rendering

    private func highlightMarkdown() {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }
        guard let storage = textView.textStorage else { return }

        let nsText = text as NSString
        let selectedRange = textView.selectedRange()

        // Update background for theme
        textView.backgroundColor = bgColor

        storage.beginEditing()

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 2
        ps.paragraphSpacing = 2

        // Reset all to Mdmdt defaults
        storage.addAttribute(.font, value: bodyFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        storage.addAttribute(.paragraphStyle, value: ps, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)

        let activeLineRange = lineRangeForLine(activeLine, in: nsText)

        // --- Frontmatter (dimmed mono) ---
        let fmColor = isDark ? NSColor(hex: "#667c89") : NSColor(hex: "#888888")
        applyPattern(#"\A---\n.+?\n---"#, in: nsText, storage: storage, options: [.dotMatchesLineSeparators]) { match in
            storage.addAttribute(.foregroundColor, value: fmColor, range: match.range)
            storage.addAttribute(.font, value: self.monoFont, range: match.range)
        }

        // --- Headings ---
        applyPattern(#"^(#{1,6})(\s+)(.+)$"#, in: nsText, storage: storage) { match in
            let wholeRange = match.range
            let hashRange = match.range(at: 1)
            let spaceRange = match.range(at: 2)
            let contentRange = match.range(at: 3)
            let level = hashRange.length

            let font: NSFont
            switch level {
            case 1: font = self.h1Font
            case 2: font = self.h2Font
            case 3: font = self.h3Font
            default: font = self.h4Font
            }
            storage.addAttribute(.font, value: font, range: contentRange)

            // Mdmdt: margin 32px 0 18px, line-height 1.5, letter-spacing 2px
            let headingPS = NSMutableParagraphStyle()
            headingPS.lineSpacing = 2
            headingPS.paragraphSpacingBefore = 8
            headingPS.paragraphSpacing = 2
            storage.addAttribute(.paragraphStyle, value: headingPS, range: wholeRange)

            // h1: bottom border (simulated with underline on last char)
            if level == 1 {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                storage.addAttribute(.underlineColor, value: self.borderColor, range: contentRange)
            }

            let cursorOnLine = self.cursorOnLine(activeLineRange, wholeRange)
            if !cursorOnLine {
                self.hideChars(hashRange, in: storage)
                self.hideChars(spaceRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.accentBlue.withAlphaComponent(0.5), range: hashRange)
                storage.addAttribute(.font, value: font, range: hashRange)
            }
        }

        // --- Code blocks ---
        var codeBlockRanges: [NSRange] = []
        var codeBlockInfos: [CodeBlockInfo] = []
        let cbPattern = #"```([^\n]*)\n(.+?)\n```"#
        applyPattern(cbPattern, in: nsText, storage: storage, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) { match in
            let wholeRange = match.range
            codeBlockRanges.append(wholeRange)

            let lang = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let bodyRange = match.range(at: 2)
            codeBlockInfos.append(CodeBlockInfo(range: wholeRange, language: lang, bodyRange: bodyRange))

            let matchStr = nsText.substring(with: wholeRange)

            // Check if cursor is inside this code block
            let cursorInBlock = self.cursorInRange(activeLineRange, wholeRange)

            // Code content: monospace + code color
            storage.addAttribute(.font, value: self.monoFont, range: bodyRange)
            storage.addAttribute(.foregroundColor, value: self.codeTextColor, range: bodyRange)

            // Opening fence line
            if let firstNL = matchStr.range(of: "\n") {
                let openLen = matchStr.distance(from: matchStr.startIndex, to: firstNL.lowerBound)
                let openFence = NSRange(location: wholeRange.location, length: openLen)

                if cursorInBlock {
                    storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openFence)
                    storage.addAttribute(.font, value: self.monoFont, range: openFence)
                } else {
                    self.hideChars(openFence, in: storage)
                }
            }

            // Closing fence line
            if let lastNL = matchStr.range(of: "\n", options: .backwards) {
                let closeStart = matchStr.distance(from: matchStr.startIndex, to: lastNL.upperBound)
                let closeFence = NSRange(location: wholeRange.location + closeStart, length: wholeRange.length - closeStart)

                if cursorInBlock {
                    storage.addAttribute(.foregroundColor, value: self.secondaryText, range: closeFence)
                    storage.addAttribute(.font, value: self.monoFont, range: closeFence)
                } else {
                    self.hideChars(closeFence, in: storage)
                }
            }
        }

        // Pass code block info to custom text view for background drawing
        textView.codeBlocks = codeBlockInfos
        textView.codeBlockBackground = codeBlockBg
        textView.codeBlockBorder = borderColor
        textView.langLabelColor = isDark ? NSColor(hex: "#9ca3af") : NSColor(hex: "#555555")
        textView.langLabelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        textView.langPillBg = isDark ? NSColor(hex: "#3a3a42") : NSColor(hex: "#dcdce0")

        // --- Syntax highlighting inside code blocks (Mdmdt CodeMirror colors) ---
        let synKeyword = isDark ? NSColor(hex: "#bb59fd") : NSColor(hex: "#7c3aed")   // purple
        let synString  = isDark ? NSColor(hex: "#02be74") : NSColor(hex: "#16a34a")    // green
        let synNumber  = isDark ? NSColor(hex: "#f59102") : NSColor(hex: "#d97706")    // orange
        let synComment = isDark ? NSColor(hex: "#667c89") : NSColor(hex: "#94a3b8")    // grey
        let synBuiltin = isDark ? NSColor(hex: "#40d7ec") : NSColor(hex: "#0891b2")    // cyan
        let synTag     = isDark ? NSColor(hex: "#e32e73") : NSColor(hex: "#dc2626")    // red/pink
        let synParam   = isDark ? NSColor(hex: "#f59102") : NSColor(hex: "#d97706")    // orange (same as number)

        for block in codeBlockInfos {
            let body = block.bodyRange
            let bodyStr = nsText.substring(with: body)

            // Comments: # ...
            self.applySyntax(#"#[^\n]*"#, in: bodyStr, offset: body.location, storage: storage, color: synComment)

            // Strings: "..." or '...' (including triple-quoted)
            self.applySyntax(#"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|\"[^\"\\]*(?:\\.[^\"\\]*)*\"|'[^'\\]*(?:\\.[^'\\]*)*'"#, in: bodyStr, offset: body.location, storage: storage, color: synString)

            // Keywords
            self.applySyntax(#"\b(import|from|as|def|class|return|if|elif|else|for|while|in|not|and|or|is|with|try|except|finally|raise|pass|break|continue|yield|lambda|global|nonlocal|assert|del|True|False|None)\b"#, in: bodyStr, offset: body.location, storage: storage, color: synKeyword)

            // Built-in functions
            self.applySyntax(#"\b(print|len|range|int|str|float|list|dict|set|tuple|type|isinstance|enumerate|zip|map|filter|sorted|open|super|self)\b"#, in: bodyStr, offset: body.location, storage: storage, color: synBuiltin)

            // Numbers
            self.applySyntax(#"\b\d+\.?\d*\b"#, in: bodyStr, offset: body.location, storage: storage, color: synNumber)

            // Decorators @
            self.applySyntax(#"@\w+"#, in: bodyStr, offset: body.location, storage: storage, color: synTag)

            // Function/method calls: word(
            self.applySyntax(#"\b(\w+)\s*(?=\()"#, in: bodyStr, offset: body.location, storage: storage, color: synBuiltin)

            // Operators
            self.applySyntax(#"[=\+\-\*/!<>&|%^~]+"#, in: bodyStr, offset: body.location, storage: storage, color: synTag)

            // Brackets
            self.applySyntax(#"[\[\](){}]"#, in: bodyStr, offset: body.location, storage: storage, color: self.textColor)
        }

        let inCodeBlock: (NSRange) -> Bool = { range in
            codeBlockRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        // --- Bold **text** (weight 800, color #cfdfff dark) ---
        applyPattern(#"\*\*(.+?)\*\*"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: self.bodyBold, range: contentRange)
            storage.addAttribute(.foregroundColor, value: self.boldColor, range: contentRange)

            let openRange = NSRange(location: match.range.location, length: 2)
            let closeRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)

            if !self.cursorInElement(match.range) {
                self.hideChars(openRange, in: storage)
                self.hideChars(closeRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openRange)
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: closeRange)
            }
        }

        // --- Italic *text* ---
        applyPattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: self.bodyItalic, range: contentRange)

            let openRange = NSRange(location: match.range.location, length: 1)
            let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)

            if !self.cursorInElement(match.range) {
                self.hideChars(openRange, in: storage)
                self.hideChars(closeRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openRange)
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: closeRange)
            }
        }

        // --- Inline code `text` ---
        applyPattern(#"`([^`\n]+)`"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: self.monoFont, range: contentRange)
            storage.addAttribute(.foregroundColor, value: self.codeTextColor, range: contentRange)
            storage.addAttribute(.backgroundColor, value: self.codeBgColor, range: contentRange)

            let openRange = NSRange(location: match.range.location, length: 1)
            let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)

            if !self.cursorInElement(match.range) {
                self.hideChars(openRange, in: storage)
                self.hideChars(closeRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openRange)
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: closeRange)
            }
        }

        // --- Links [text](url) — color #3e69d7, weight 500, no underline ---
        let linkFont = NSFontManager.shared.convert(self.bodyFont, toHaveTrait: .unboldFontMask)
        applyPattern(#"\[([^\]]+)\]\(([^\)]+)\)"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            let textRange = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: self.accentBlue, range: textRange)
            // Medium weight for links
            if let medFont = NSFont(name: "PingFang SC Medium", size: 16) {
                storage.addAttribute(.font, value: medFont, range: textRange)
            }

            let openBracket = NSRange(location: match.range.location, length: 1)
            let afterText = textRange.location + textRange.length
            let tailLen = match.range.location + match.range.length - afterText
            let tailRange = NSRange(location: afterText, length: tailLen)

            if !self.cursorInElement(match.range) {
                self.hideChars(openBracket, in: storage)
                self.hideChars(tailRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openBracket)
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: tailRange)
            }
        }

        // --- Images ![alt](url) ---
        applyPattern(#"!\[([^\]]*)\]\(([^\)]+)\)"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            storage.addAttribute(.foregroundColor, value: NSColor(hex: "#8250df"), range: match.range)
        }

        // --- Blockquotes > text ---
        var quoteMatches: [NSTextCheckingResult] = []
        applyPattern(#"^(>\s?)(.*)$"#, in: nsText, storage: storage) { match in
            quoteMatches.append(match)

            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)

            let quotePS = NSMutableParagraphStyle()
            quotePS.lineSpacing = 2
            quotePS.paragraphSpacing = 0
            quotePS.headIndent = 20
            quotePS.firstLineHeadIndent = 20

            // Blockquote text inherits body color in Mdmdt
            storage.addAttribute(.foregroundColor, value: self.textColor, range: contentRange)
            storage.addAttribute(.paragraphStyle, value: quotePS, range: match.range)

            if !self.cursorInElement(match.range) {
                self.hideChars(markerRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.accentBlue.withAlphaComponent(0.5), range: markerRange)
            }
        }

        // Group consecutive > lines into blockquote blocks
        var blockquoteInfos: [BlockquoteInfo] = []
        if !quoteMatches.isEmpty {
            var groupStart = quoteMatches[0].range
            var groupEnd = NSMaxRange(groupStart)

            for i in 1..<quoteMatches.count {
                let thisRange = quoteMatches[i].range
                // Check if this line is consecutive (immediately after previous)
                if thisRange.location <= groupEnd + 1 {
                    groupEnd = NSMaxRange(thisRange)
                } else {
                    let combined = NSRange(location: groupStart.location, length: groupEnd - groupStart.location)
                    let firstLine = nsText.substring(with: quoteMatches[i-1].range)
                    let isCallout = nsText.substring(with: NSRange(location: groupStart.location, length: min(10, groupStart.length))).contains("[!")
                    blockquoteInfos.append(BlockquoteInfo(range: combined, isCallout: isCallout, calloutType: ""))
                    groupStart = thisRange
                    groupEnd = NSMaxRange(thisRange)
                }
            }
            let combined = NSRange(location: groupStart.location, length: groupEnd - groupStart.location)
            let firstText = nsText.substring(with: quoteMatches[0].range)
            let isCallout = nsText.substring(with: NSRange(location: groupStart.location, length: min(groupStart.length, nsText.length - groupStart.location))).contains("[!")
            blockquoteInfos.append(BlockquoteInfo(range: combined, isCallout: isCallout, calloutType: ""))
        }

        // Pass to text view for background drawing
        // Mdmdt: --color-1-0-b = rgba(62, 105, 215, 0.12)
        let quoteBgColor = NSColor(hex: "#3e69d7").withAlphaComponent(0.12)
        textView.blockquotes = blockquoteInfos
        textView.quoteBg = quoteBgColor
        textView.quoteBorder = accentBlue

        // --- Strikethrough ~~text~~ (red line, grey text) ---
        applyPattern(#"~~(.+?)~~"#, in: nsText, storage: storage) { match in
            guard !inCodeBlock(match.range) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            storage.addAttribute(.strikethroughColor, value: self.strikeColor, range: contentRange)
            storage.addAttribute(.foregroundColor, value: self.secondaryText, range: contentRange)

            let openRange = NSRange(location: match.range.location, length: 2)
            let closeRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)

            if !self.cursorInElement(match.range) {
                self.hideChars(openRange, in: storage)
                self.hideChars(closeRange, in: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: openRange)
                storage.addAttribute(.foregroundColor, value: self.secondaryText, range: closeRange)
            }
        }

        // --- Lists (Mdmdt: padding-left 36px, marker li margin-top 6px) ---
        applyPattern(#"^(\s*[-*+]\s)(.+)$"#, in: nsText, storage: storage) { match in
            let markerRange = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: self.secondaryText, range: markerRange)

            let listPS = NSMutableParagraphStyle()
            listPS.lineSpacing = 2
            listPS.paragraphSpacing = 2
            listPS.headIndent = 36
            listPS.firstLineHeadIndent = 16
            storage.addAttribute(.paragraphStyle, value: listPS, range: match.range)
        }

        // --- Horizontal rules (1px #464b50) ---
        applyPattern(#"^(---|\*\*\*|___)$"#, in: nsText, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: self.borderColor, range: match.range)
        }

        storage.endEditing()

        // Trigger redraw for custom code block backgrounds
        textView.needsDisplay = true

        if selectedRange.location + selectedRange.length <= nsText.length {
            textView.setSelectedRange(selectedRange)
        }
    }

    // MARK: - Helpers

    private func applyPattern(_ pattern: String, in nsText: NSString, storage: NSTextStorage, options: NSRegularExpression.Options = [.anchorsMatchLines], handler: (NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullRange = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: nsText as String, range: fullRange) {
            handler(match)
        }
    }

    private func applySyntax(_ pattern: String, in text: String, offset: Int, storage: NSTextStorage, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let nsText = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let range = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    private func hideChars(_ range: NSRange, in storage: NSTextStorage) {
        let tinyFont = NSFont.systemFont(ofSize: 0.01)
        storage.addAttribute(.font, value: tinyFont, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
    }

    private func cursorOnLine(_ activeLineRange: NSRange?, _ matchRange: NSRange) -> Bool {
        guard let alr = activeLineRange else { return false }
        return NSIntersectionRange(alr, matchRange).length > 0
    }

    /// Check if cursor is within or immediately adjacent to a specific element range
    private func cursorInElement(_ matchRange: NSRange) -> Bool {
        let sel = textView.selectedRange()
        // If there's a selection, check if it overlaps with the match
        if sel.length > 0 {
            return NSIntersectionRange(sel, matchRange).length > 0
        }
        // Cursor (no selection): check if it's inside or at the edges of the element
        return sel.location >= matchRange.location && sel.location <= matchRange.location + matchRange.length
    }

    private func cursorInRange(_ activeLineRange: NSRange?, _ blockRange: NSRange) -> Bool {
        let cursorLoc = textView.selectedRange().location
        return cursorLoc >= blockRange.location && cursorLoc <= blockRange.location + blockRange.length
    }

    private func lineRangeForLine(_ lineNum: Int, in nsText: NSString) -> NSRange? {
        guard lineNum >= 0 else { return nil }
        var current = 0
        var start = 0
        while start < nsText.length {
            let lineEnd = nsText.range(of: "\n", options: [], range: NSRange(location: start, length: nsText.length - start))
            let end = lineEnd.location == NSNotFound ? nsText.length : lineEnd.location + 1
            if current == lineNum {
                return NSRange(location: start, length: end - start)
            }
            start = end
            current += 1
        }
        return nil
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
}
