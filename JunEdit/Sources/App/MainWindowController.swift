import Cocoa

class MainWindowController: NSWindowController {
    private let splitView = NSSplitViewController()
    private var previewItem: NSSplitViewItem?

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

        self.init(window: window)
        setupSplitView()
        setupToolbar()
        setupMenu()
    }

    private func setupSplitView() {
        // Three columns: sidebar | editor | preview (preview hidden by default)
        let sidebar = SidebarViewController()
        let editor = EditorViewController()

        sidebar.onPostSelected = { [weak editor] (post: BlogPost) in
            editor?.loadPost(post)
        }

        sidebar.onPostDeleted = { [weak editor] (post: BlogPost) in
            // Clear editor if deleted post was open
            if editor?.currentPost?.slug == post.slug {
                editor?.clearPost()
            }
            // Deploy deletion to website
            BuildRunner.shared.deploy()
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
        let previewVC = PreviewViewController()
        let pItem = NSSplitViewItem(viewController: previewVC)
        pItem.minimumThickness = 300
        pItem.canCollapse = true
        pItem.isCollapsed = true
        previewItem = pItem

        splitView.addSplitViewItem(sidebarItem)
        splitView.addSplitViewItem(editorItem)
        splitView.addSplitViewItem(pItem)
        splitView.splitView.dividerStyle = .thin

        window?.contentViewController = splitView
    }

    // MARK: - Toolbar (top-right buttons)

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar
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
            // Already in preview-only mode — restore editor, hide preview
            editorItem.animator().isCollapsed = false
            previewItemLocal.animator().isCollapsed = true
        } else {
            // Enter preview-only mode: hide editor, show preview
            editorItem.animator().isCollapsed = true
            previewItemLocal.animator().isCollapsed = false
        }
    }

    @objc private func buildCurrentPost() {
        guard let slug = editorVC?.currentPost?.slug else { return }
        editorVC?.save()
        BuildRunner.shared.buildPost(slug: slug) { [weak self] success in
            if success {
                self?.showBuildPreview()
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
}

// MARK: - NSToolbarDelegate

private extension NSToolbarItem.Identifier {
    static let sidebarToggle = NSToolbarItem.Identifier("sidebarToggle")
    static let formatToggle = NSToolbarItem.Identifier("formatToggle")
    static let splitToggle = NSToolbarItem.Identifier("splitToggle")
    static let previewToggle = NSToolbarItem.Identifier("previewToggle")
    static let presentationToggle = NSToolbarItem.Identifier("presentationToggle")

}

extension MainWindowController: NSToolbarDelegate {

    private func makeItem(_ id: NSToolbarItem.Identifier, imageName: String, label: String, tip: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = tip
        let img = NSImage(named: imageName)
        img?.isTemplate = true
        item.image = img
        item.action = action
        item.target = self
        return item
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch itemIdentifier {
        case .sidebarToggle:
            return makeItem(itemIdentifier, imageName: "icon_sidebar_left", label: "Sidebar", tip: "Toggle Sidebar (⌘1)", action: #selector(toggleSidebar))
        case .formatToggle:
            return makeItem(itemIdentifier, imageName: "icon_format", label: "Build", tip: "Build Current Post (⌘B)", action: #selector(buildCurrentPost))
        case .splitToggle:
            return makeItem(itemIdentifier, imageName: "icon_editor_split", label: "Split", tip: "Toggle Preview (⌘\\)", action: #selector(togglePreview))
        case .previewToggle:
            return makeItem(itemIdentifier, imageName: "icon_preview", label: "Preview", tip: "Preview Only (⌘D)", action: #selector(togglePreviewOnly))
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .sidebarToggle,
            .formatToggle,
            .splitToggle,
            .previewToggle,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarToggle, .formatToggle, .splitToggle, .previewToggle, .flexibleSpace]
    }
}
