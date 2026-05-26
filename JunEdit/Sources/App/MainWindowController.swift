import Cocoa

class MainWindowController: NSWindowController {
    private let splitView = NSSplitViewController()
    private var previewItem: NSSplitViewItem?
    private var chatItem: NSSplitViewItem?
    private var activePopover: AIPromptPopover?

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

        // AI menu
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
        aiMenu.addItem(NSMenuItem(title: "Cancel AI", action: #selector(cancelAI), keyEquivalent: "."))
        let aiMenuItem = NSMenuItem()
        aiMenuItem.submenu = aiMenu
        mainMenu.addItem(aiMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Accessors

    private var editorVC: EditorViewController? {
        splitView.splitViewItems.count > 1
            ? splitView.splitViewItems[1].viewController as? EditorViewController
            : nil
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

        // Generate slug from current date/time
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        let slug = "new-post-\(df.string(from: Date()))"

        let postDir = blogDir.appendingPathComponent("posts/\(slug)")
        let assetsDir = postDir.appendingPathComponent("assets")
        let mdFile = postDir.appendingPathComponent("index.md")

        do {
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
            let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withDashSeparatorInDate])
            let template = """
            ---
            title: "New Post"
            date: \(today)
            author: "Jun He"
            tags: []
            ---

            Write your post here.
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

        // Show the preview column
        if let item = previewItem {
            item.animator().isCollapsed = false
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

    @objc private func aiInlineReplace() {
        guard let editor = editorVC else { return }
        let selected = editor.selectedText()
        guard let selected = selected, !selected.isEmpty else {
            updateStatusBar(status: "Select text first")
            return
        }

        let popover = AIPromptPopover(placeholder: "How should AI rewrite this?") { [weak self, weak editor] prompt in
            guard let self = self, let editor = editor else { return }
            self.updateStatusBar(status: "AI thinking...")

            var result = ""
            AIRunner.shared.run(prompt: prompt, context: selected, onOutput: { chunk in
                result += chunk
            }, onComplete: { [weak self] error in
                self?.activePopover?.close()
                self?.activePopover = nil
                if error == nil {
                    editor.replaceSelection(with: result)
                    self?.updateStatusBar(status: "AI done")
                } else {
                    self?.updateStatusBar(status: "AI error")
                }
            })
        }
        activePopover = popover
        let rect = editor.cursorRect()
        popover.show(relativeTo: rect, of: editor.editorView, preferredEdge: .maxY)
    }

    @objc private func aiAppendBelow() {
        guard let editor = editorVC else { return }

        let popover = AIPromptPopover(placeholder: "What should AI write?") { [weak self, weak editor] prompt in
            guard let self = self, let editor = editor else { return }
            self.updateStatusBar(status: "AI thinking...")

            let context = editor.documentText()
            var result = ""
            AIRunner.shared.run(prompt: prompt, context: context, onOutput: { chunk in
                result += chunk
            }, onComplete: { [weak self] error in
                self?.activePopover?.close()
                self?.activePopover = nil
                if error == nil {
                    editor.appendBelowCursor(result)
                    self?.updateStatusBar(status: "AI done")
                } else {
                    self?.updateStatusBar(status: "AI error")
                }
            })
        }
        activePopover = popover
        let rect = editor.cursorRect()
        popover.show(relativeTo: rect, of: editor.editorView, preferredEdge: .maxY)
    }

    @objc private func toggleAIChat() {
        guard let item = chatItem else { return }
        item.animator().isCollapsed.toggle()
    }

    @objc private func cancelAI() {
        AIRunner.shared.cancel()
        activePopover?.close()
        activePopover = nil
        updateStatusBar(status: "AI cancelled")
    }
}

