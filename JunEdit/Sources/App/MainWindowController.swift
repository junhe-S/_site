import Cocoa

class MainWindowController: NSWindowController {
    private let splitView = NSSplitViewController()
    private var previewItem: NSSplitViewItem?
    private var chatItem: NSSplitViewItem?
    // Shared background — matches editor Mdmdt theme
    private var contentBgColor: NSColor {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(hex: "#1b1b1f") : NSColor(hex: "#fafafc")
    }

    // Title bar
    private let titleBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "JunEdit")

    // Status bar
    private let statusBar = NSView()
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let lineCountLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Ready")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("JunEditMainWindow")
        window.minSize = NSSize(width: 600, height: 400)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        self.init(window: window)
        setupSplitView()
        setupTitleBar()
        setupStatusBar()
        setupMenu()
    }

    private func setupSplitView() {
        // Three columns: sidebar | editor | preview (preview hidden by default)
        let sidebar = SidebarViewController()
        let editor = EditorViewController()

        sidebar.onPostSelected = { [weak editor, weak self] (post: BlogPost) in
            editor?.loadPost(post)
            self?.updateTitleBar(post.slug)
        }

        sidebar.onPostDeleted = { [weak editor] (post: BlogPost) in
            if editor?.currentPost?.slug == post.slug {
                editor?.clearPost()
            }
        }

        // Update status bar on edits (no live build)
        let previewVC = PreviewViewController()
        editor.onContentChanged = { [weak self] (content: String) in
            let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = content.components(separatedBy: "\n").count
            self?.updateStatusBar(words: words, lines: lines)
        }

        // Sidebar with native vibrancy
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true

        // Editor
        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 400

        // Preview (third column, starts collapsed)
        let pItem = NSSplitViewItem(viewController: previewVC)
        pItem.minimumThickness = 300
        pItem.canCollapse = true
        pItem.isCollapsed = true
        previewItem = pItem

        // AI Chat panel (fourth column, starts collapsed)
        let chatVC = AIChatViewController()
        chatVC.documentContext = { [weak editor] in editor?.documentText() ?? "" }
        chatVC.setInsertHandler { [weak editor] text in
            editor?.insertAtCursor(text)
        }
        let cItem = NSSplitViewItem(viewController: chatVC)
        cItem.minimumThickness = 280
        cItem.canCollapse = true
        cItem.isCollapsed = true
        chatItem = cItem

        splitView.addSplitViewItem(sidebarItem)
        splitView.addSplitViewItem(editorItem)
        splitView.addSplitViewItem(pItem)
        splitView.addSplitViewItem(cItem)
        splitView.splitView.dividerStyle = .thin

        // Wrap titleBar + splitView + statusBar in a container
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        splitView.view.translatesAutoresizingMaskIntoConstraints = false

        let containerVC = NSViewController()
        containerVC.view = container
        container.addSubview(titleBar)
        container.addSubview(splitView.view)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: container.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 38),

            splitView.view.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            splitView.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        window?.contentViewController = containerVC
        containerVC.addChild(splitView)
    }

    // MARK: - Title Bar

    private func setupTitleBar() {
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = contentBgColor.cgColor

        // Title label centered
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titleBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
        ])
    }

    /// Update the title bar text (e.g. show current post name)
    func updateTitleBar(_ text: String) {
        titleLabel.stringValue = text
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = contentBgColor.cgColor

        // Left side: icon buttons
        let sidebarBtn = makeStatusButton(imageName: "icon_sidebar_left", tip: "Toggle Sidebar (⌘1)", action: #selector(toggleSidebar))
        let buildBtn = makeStatusButton(imageName: "icon_format", tip: "Build Current Post (⌘B)", action: #selector(buildCurrentPost))
        let splitBtn = makeStatusButton(imageName: "icon_editor_split", tip: "Toggle Preview (⌘\\)", action: #selector(togglePreview))
        let previewBtn = makeStatusButton(imageName: "icon_preview", tip: "Preview Only (⌘D)", action: #selector(togglePreviewOnly))

        let aiChatBtn = makeStatusButton(imageName: NSImage.touchBarComposeTemplateName, tip: "Toggle AI Chat (⇧⌘L)", action: #selector(toggleAIChat))

        let buttonStack = NSStackView(views: [sidebarBtn, buildBtn, splitBtn, previewBtn, aiChatBtn])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 2
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        // Right side: status labels
        styleStatusLabel(wordCountLabel)
        styleStatusLabel(lineCountLabel)
        styleStatusLabel(statusLabel)

        let labelStack = NSStackView(views: [statusLabel, makeSeparatorDot(), wordCountLabel, makeSeparatorDot(), lineCountLabel])
        labelStack.orientation = .horizontal
        labelStack.spacing = 6
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        statusBar.addSubview(buttonStack)
        statusBar.addSubview(labelStack)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
            buttonStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            labelStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            labelStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
    }

    private func makeStatusButton(imageName: String, tip: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.toolTip = tip
        btn.target = self
        btn.action = action

        let img = NSImage(named: imageName)
        img?.isTemplate = true
        btn.image = img
        btn.imageScaling = .scaleProportionallyDown

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 28),
            btn.heightAnchor.constraint(equalToConstant: 24),
        ])
        return btn
    }

    private func styleStatusLabel(_ label: NSTextField) {
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeSeparatorDot() -> NSTextField {
        let dot = NSTextField(labelWithString: "·")
        dot.font = NSFont.systemFont(ofSize: 11)
        dot.textColor = .tertiaryLabelColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        return dot
    }

    /// Call this to update status bar info
    func updateStatusBar(words: Int? = nil, lines: Int? = nil, status: String? = nil) {
        if let w = words { wordCountLabel.stringValue = "\(w) words" }
        if let l = lines { lineCountLabel.stringValue = "Ln \(l)" }
        if let s = status { statusLabel.stringValue = s }
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About JunEdit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit JunEdit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New Post", action: #selector(newPost), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(savePost), keyEquivalent: "s"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Set Blog Directory...", action: #selector(setBlogDirectory), keyEquivalent: ","))
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "1"))
        viewMenu.addItem(NSMenuItem(title: "Toggle Preview", action: #selector(togglePreview), keyEquivalent: "\\"))
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Build menu
        let buildMenu = NSMenu(title: "Build")
        buildMenu.addItem(NSMenuItem(title: "Build Current Post", action: #selector(buildCurrentPost), keyEquivalent: "b"))
        buildMenu.addItem(NSMenuItem(title: "Build All Posts", action: #selector(buildAllPosts), keyEquivalent: "B"))
        buildMenu.addItem(.separator())
        buildMenu.addItem(NSMenuItem(title: "Deploy", action: #selector(deploySite), keyEquivalent: "d"))
        let buildMenuItem = NSMenuItem()
        buildMenuItem.submenu = buildMenu
        mainMenu.addItem(buildMenuItem)

        // AI menu (shortcuts shown in menu, actual handling via local event monitor)
        let aiMenu = NSMenu(title: "AI")
        let inlineItem = NSMenuItem(title: "AI Rewrite Selection", action: #selector(aiInlineReplace), keyEquivalent: "r")
        inlineItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(inlineItem)
        let appendItem = NSMenuItem(title: "AI Append Below", action: #selector(aiAppendBelow), keyEquivalent: "a")
        appendItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(appendItem)
        aiMenu.addItem(.separator())
        let chatToggleItem = NSMenuItem(title: "Toggle AI Chat", action: #selector(toggleAIChat), keyEquivalent: "l")
        chatToggleItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(chatToggleItem)
        aiMenu.addItem(.separator())
        let bergenItem = NSMenuItem(title: "Bergen Annotate URL", action: #selector(aiBergenAnnotate), keyEquivalent: "g")
        bergenItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(bergenItem)
        aiMenu.addItem(.separator())
        let cancelItem = NSMenuItem(title: "Cancel AI", action: #selector(cancelAI), keyEquivalent: ".")
        cancelItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(cancelItem)
        let aiMenuItem = NSMenuItem()
        aiMenuItem.submenu = aiMenu
        mainMenu.addItem(aiMenuItem)

        NSApp.mainMenu = mainMenu

        // Local event monitor — catches shortcuts regardless of responder chain
        installAIShortcutMonitor()
    }

    private var shortcutMonitor: Any?

    private func installAIShortcutMonitor() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Must have Cmd+Shift, and only Cmd+Shift (ignore if other modifiers present)
            guard flags.contains(.command), flags.contains(.shift) else { return event }

            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            NSLog("JunEdit: shortcut monitor key=%@ flags=%lu", key, flags.rawValue)

            switch key {
            case "r":
                NSLog("JunEdit: Cmd+Shift+R → aiInlineReplace")
                self.aiInlineReplace()
                return nil  // consumed
            case "a":
                NSLog("JunEdit: Cmd+Shift+A → aiAppendBelow")
                self.aiAppendBelow()
                return nil
            case "l":
                self.toggleAIChat()
                return nil
            case "g":
                NSLog("JunEdit: Cmd+Shift+G → aiBergenAnnotate")
                self.aiBergenAnnotate()
                return nil
            case ".":
                self.cancelAI()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - Accessors

    private var editorVC: EditorViewController? {
        splitView.splitViewItems.count > 1
            ? splitView.splitViewItems[1].viewController as? EditorViewController
            : nil
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    private var sidebarVC: SidebarViewController? {
        splitView.splitViewItems.first?.viewController as? SidebarViewController
    }

    private var chatVC: AIChatViewController? {
        chatItem?.viewController as? AIChatViewController
    }

    // MARK: - Actions

    @objc private func newPost() {
        guard let blogDir = BlogSettings.shared.blogDirectory else {
            setBlogDirectory()
            return
        }

        // Use whichever section is selected in sidebar (defaults to "posts")
        let section = sidebarVC?.selectedSection ?? "posts"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        let slug = "new-\(section)-\(df.string(from: Date()))"

        let postDir = blogDir.appendingPathComponent("\(section)/\(slug)")
        let assetsDir = postDir.appendingPathComponent("assets")
        let mdFile = postDir.appendingPathComponent("index.md")

        do {
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
            let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withDashSeparatorInDate])
            let template = """
            ---
            title: "New \(section.capitalized)"
            date: \(today)
            author: "Jun He"
            tags: []
            ---

            Write here.
            """
            try template.write(to: mdFile, atomically: true, encoding: .utf8)
            sidebarVC?.refreshPosts()
            let post = BlogPost(slug: slug, path: mdFile)
            editorVC?.loadPost(post)
        } catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }

    @objc private func savePost() { editorVC?.save() }

    @objc private func setBlogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your blog root directory (containing posts/ and build.py)"
        panel.prompt = "Select"
        panel.directoryURL = BlogSettings.shared.blogDirectory ?? URL(fileURLWithPath: NSHomeDirectory())

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            NSLog("JunEdit: Selected blog directory: \(url.path)")
            BlogSettings.shared.blogDirectory = url
            sidebarVC?.refreshPosts()
        }
    }

    @objc private func toggleSidebar() {
        guard let item = splitView.splitViewItems.first else { return }
        item.animator().isCollapsed.toggle()
    }

    @objc private func togglePreview() {
        guard splitView.splitViewItems.count > 2 else { return }
        let editorItem = splitView.splitViewItems[1]
        let previewItemLocal = splitView.splitViewItems[2]

        if previewItemLocal.isCollapsed {
            // Show preview alongside editor
            editorItem.animator().isCollapsed = false
            previewItemLocal.animator().isCollapsed = false
        } else {
            // Hide preview, ensure editor is visible
            previewItemLocal.animator().isCollapsed = true
            editorItem.animator().isCollapsed = false
        }
    }

    @objc private func togglePreviewOnly() {
        guard splitView.splitViewItems.count > 2 else { return }
        let editorItem = splitView.splitViewItems[1]
        let previewItemLocal = splitView.splitViewItems[2]

        if editorItem.isCollapsed {
            editorItem.animator().isCollapsed = false
            previewItemLocal.animator().isCollapsed = true
        } else {
            editorItem.animator().isCollapsed = true
            previewItemLocal.animator().isCollapsed = false
        }
    }

    @objc private func buildCurrentPost() {
        guard let slug = editorVC?.currentPost?.slug else { return }
        editorVC?.save()
        updateStatusBar(status: "Building...")

        BuildRunner.shared.buildPost(slug: slug) { [weak self] success in
            if success {
                self?.updateStatusBar(status: "Built")
                self?.showBuildPreview()
            } else {
                self?.updateStatusBar(status: "Build failed")
            }
        }
    }

    private func showBuildPreview() {
        guard let post = editorVC?.currentPost else { return }
        let htmlFile = post.path.deletingLastPathComponent().appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: htmlFile.path) else { return }

        // Show the preview column and split editor/preview equally
        if let item = previewItem {
            item.animator().isCollapsed = false

            // Give editor and preview equal width
            let editorItem = splitView.splitViewItems[1]
            let available = editorItem.viewController.view.frame.width + item.viewController.view.frame.width
            let half = available / 2
            editorItem.viewController.view.setFrameSize(NSSize(width: half, height: editorItem.viewController.view.frame.height))
            item.viewController.view.setFrameSize(NSSize(width: half, height: item.viewController.view.frame.height))
            splitView.splitView.adjustSubviews()
        }

        // Load the built HTML
        if let previewVC = previewItem?.viewController as? PreviewViewController {
            previewVC.loadHTMLFile(htmlFile)
        }
    }

    @objc private func buildAllPosts() {
        editorVC?.save()
        BuildRunner.shared.buildAll()
    }

    @objc private func deploySite() {
        editorVC?.save()
        BuildRunner.shared.deploy()
    }

    // MARK: - AI Actions

    private var currentInlineBar: AIInlineBar?

    @objc func aiInlineReplace() {
        guard let editor = editorVC else { return }
        let selected = editor.selectedText()
        guard let selected = selected, !selected.isEmpty else {
            updateStatusBar(status: "Select text first")
            return
        }

        NSLog("JunEdit AI: aiInlineReplace triggered, selected=%d chars", selected.count)
        showInlineBar(mode: .rewrite, editor: editor, context: selected)
    }

    @objc func aiAppendBelow() {
        guard let editor = editorVC else { return }
        NSLog("JunEdit AI: aiAppendBelow triggered")
        showInlineBar(mode: .append, editor: editor, context: editor.documentText())
    }

    private enum AIMode { case rewrite, append }

    private func showInlineBar(mode: AIMode, editor: EditorViewController, context: String) {
        dismissInlineBar()
        let bar = AIInlineBar()
        currentInlineBar = bar

        bar.onSubmit = { [weak self, weak editor, weak bar] prompt in
            guard let self = self, let editor = editor, let bar = bar else { return }
            self.updateStatusBar(status: "AI thinking...")

            let systemPrefix: String
            switch mode {
            case .rewrite:
                systemPrefix = "Rewrite the following text according to the user's instruction. Output ONLY the rewritten text, no explanations, no commentary, no preamble."
            case .append:
                systemPrefix = "Write content to append below the cursor based on the user's instruction. Output ONLY the content to insert, no explanations, no commentary, no preamble."
            }
            let fullPrompt = "\(systemPrefix)\n\nInstruction: \(prompt)"
            var result = ""
            AIRunner.shared.run(prompt: fullPrompt, context: context, onOutput: { chunk in
                result += chunk
            }, onComplete: { [weak self, weak bar] error in
                if error == nil {
                    bar?.showResult(result.trimmingCharacters(in: .whitespacesAndNewlines))
                    self?.updateStatusBar(status: "Accept or Reject")
                } else {
                    self?.dismissInlineBar()
                    self?.updateStatusBar(status: "AI error")
                }
            })
        }

        bar.onAccept = { [weak self, weak editor] text in
            switch mode {
            case .rewrite: editor?.replaceSelection(with: text)
            case .append:  editor?.appendBelowCursor(text)
            }
            self?.dismissInlineBar()
            self?.updateStatusBar(status: "AI accepted")
        }

        bar.onReject = { [weak self] in
            self?.dismissInlineBar()
            self?.updateStatusBar(status: "AI rejected")
        }

        bar.showBelow(screenPoint: editor.selectionScreenPoint(), parentWindow: window)
    }

    // MARK: - Bergen Annotate

    private static let bergenAnnotatePrompt = """
    You are a Norwegian language learning assistant. Given a Norwegian article, produce a Markdown file for a Bergen blog post with vocabulary annotations at two levels.

    OUTPUT FORMAT (output ONLY the markdown, no explanations):

    ---
    title: "[Article headline]"
    date: [YYYY-MM-DD]
    author: "AI Generation"
    tags: ["Norwegian", ...]
    ---

    # [Headline]

    *[Author, Source]*

    ---

    ![Caption](fig_01.jpg)

    [Article body with annotations]

    <div style="height: 12rem"></div>

    ANNOTATION RULES:

    1. ADVANCED words (5-8 per article section): Use annotate blocks.

    ```text {annotate}
    [Original Norwegian sentence exactly as written.]
    ---
    word | root "meaning" + root "meaning" (Language) | English translation
    ```

    - Pick 3-5 words per block. Alternate blocks every 2-3 paragraphs.
    - Etymology: bold roots with meanings, e.g. gegn "against" + síða "side" (Old Norse)

    2. MEDIUM words (scattered in regular paragraphs): Use inline hover tooltips.

    **displayed_word**`dictionary_form` · *English translation* · etymology with *italic_foreign_terms*

    - Use each word only ONCE in the whole article.
    - Keep the original sentence intact.

    GUIDELINES:
    - Keep ALL original Norwegian text — do not summarize or skip paragraphs.
    - Annotate blocks should contain complete sentences copied verbatim.
    - Advanced: compound words, archaic forms, idioms, formal/literary vocabulary.
    - Medium: common but non-obvious words a B1-B2 learner would benefit from.
    - Etymology abbreviations: ON (Old Norse), MLG (Middle Low German), Latin, Greek, French, German.
    - Do NOT add a legend section at the end.
    - One hero image reference at the top only (fig_01.jpg with the caption provided).
    """

    @objc func aiBergenAnnotate() {
        // Show URL input dialog
        let alert = NSAlert()
        alert.messageText = "Bergen Annotate"
        alert.informativeText = "Enter a Bergens Tidende URL, or leave empty to pick from latest articles."
        alert.addButton(withTitle: "Annotate")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        input.placeholderString = "https://www.bt.no/..."
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let url = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if url.isEmpty {
            // Fetch latest articles and let user pick
            updateStatusBar(status: "Fetching BT articles...")
            BTScraper.fetchLatestURLs { [weak self] urls in
                guard !urls.isEmpty else {
                    self?.updateStatusBar(status: "No articles found")
                    return
                }
                self?.showArticlePicker(urls: urls)
            }
        } else {
            processArticleURL(url)
        }
    }

    private func showArticlePicker(urls: [String]) {
        let alert = NSAlert()
        alert.messageText = "Pick an article"
        alert.informativeText = "Select from latest BT articles:"
        alert.addButton(withTitle: "Annotate")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 500, height: 28), pullsDown: false)
        for url in urls {
            // Show slug part of URL for readability
            let slug = url.components(separatedBy: "/").last ?? url
            popup.addItem(withTitle: slug.replacingOccurrences(of: "-", with: " "))
            popup.lastItem?.representedObject = url
        }
        alert.accessoryView = popup

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              let selectedURL = popup.selectedItem?.representedObject as? String else { return }
        processArticleURL(selectedURL)
    }

    private func processArticleURL(_ url: String) {
        updateStatusBar(status: "Scraping article...")

        BTScraper.fetch(url: url) { [weak self] article in
            guard let self = self, let article = article else {
                self?.updateStatusBar(status: "Scrape failed")
                return
            }

            // Create a new Bergen post directory
            guard let blogDir = BlogSettings.shared.blogDirectory else { return }

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd-HHmmss"
            let slug = "bergen-\(df.string(from: Date()))"
            let postDir = blogDir.appendingPathComponent("bergen/\(slug)")
            let mdFile = postDir.appendingPathComponent("index.md")

            do {
                try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)
            } catch {
                self.updateStatusBar(status: "Failed to create directory")
                return
            }

            // Download hero image if available
            let imageCaption = article.imageCaption ?? "Foto: Bergens Tidende"
            if let imgURL = article.imageURL {
                let imgDest = postDir.appendingPathComponent("fig_01.jpg")
                BTScraper.downloadImage(url: imgURL, to: imgDest) { _ in }
            }

            // Build article text for AI context
            let articleText = article.paragraphs.joined(separator: "\n\n")
            let context = """
            Source: \(article.sourceURL)
            Headline: \(article.headline)
            Image caption: \(imageCaption)

            \(articleText)
            """

            self.updateStatusBar(status: "AI annotating...")

            // Run AI to generate annotated markdown
            var result = ""
            AIRunner.shared.run(
                prompt: Self.bergenAnnotatePrompt,
                context: context,
                onOutput: { chunk in
                    result += chunk
                    self.updateStatusBar(status: "AI annotating... \(result.count) chars")
                },
                onComplete: { error in
                    if let error = error {
                        NSLog("JunEdit Bergen: AI error: %@", error.localizedDescription)
                        self.updateStatusBar(status: "AI error")
                        return
                    }

                    // Write the generated markdown
                    let markdown = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try markdown.write(to: mdFile, atomically: true, encoding: .utf8)
                        self.sidebarVC?.refreshPosts()
                        let post = BlogPost(slug: slug, path: mdFile)
                        self.editorVC?.loadPost(post)
                        self.updateStatusBar(status: "Bergen article created")
                        self.updateTitleBar(slug)
                    } catch {
                        self.updateStatusBar(status: "Write failed")
                    }
                }
            )
        }
    }

    @objc func toggleAIChat() {
        guard let item = chatItem else { return }
        item.animator().isCollapsed.toggle()
    }

    @objc func cancelAI() {
        AIRunner.shared.cancel()
        dismissInlineBar()
        updateStatusBar(status: "AI cancelled")
    }

    private func dismissInlineBar() {
        if let bar = currentInlineBar {
            bar.dismiss()
            currentInlineBar = nil
        }
        // Restore focus to main window so editor keeps working
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    deinit {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

