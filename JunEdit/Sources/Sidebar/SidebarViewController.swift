import Cocoa

/// Sidebar with collapsible sections matching site navigation: Post, Research, Data, Bergen.
class SidebarViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let searchField = NSSearchField()

    /// Section model
    private struct Section {
        let name: String      // display name (capitalized)
        let dirName: String   // folder name (lowercase)
        var posts: [BlogPost]
    }

    private var sections: [Section] = []
    private var allSections: [Section] = []  // unfiltered

    var onPostSelected: ((BlogPost) -> Void)?
    var onPostDeleted: ((BlogPost) -> Void)?

    /// Returns the directory name of the currently selected section (e.g. "posts", "bergen")
    /// Falls back to "posts" if nothing is selected.
    var selectedSection: String {
        let row = outlineView.selectedRow
        guard row >= 0 else { return "posts" }
        let item = outlineView.item(atRow: row)

        // If a post is selected, find its parent section
        if let post = item as? BlogPost {
            for sec in sections {
                if sec.posts.contains(where: { $0.slug == post.slug && $0.path == post.path }) {
                    return sec.dirName
                }
            }
        }

        // If a section header is selected
        if let name = item as? String,
           let sec = sections.first(where: { $0.name == name }) {
            return sec.dirName
        }

        return "posts"
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .sidebar
        effectView.state = .followsWindowActiveState
        view = effectView

        setupSearchField()
        setupOutlineView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshPosts()
    }

    // MARK: - Search

    private func setupSearchField() {
        searchField.placeholderString = "Search"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: 12)
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.target = self
        searchField.action = #selector(searchChanged)
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // MARK: - Outline View

    private func setupOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Col"))
        column.title = ""
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 36
        outlineView.style = .sourceList
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.target = self
        outlineView.action = #selector(itemClicked)
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.backgroundColor = .clear
        outlineView.indentationPerLevel = 12

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2
        outlineView.addGestureRecognizer(rightClick)

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data

    func refreshPosts() {
        guard BlogSettings.shared.blogDirectory != nil else {
            allSections = []
            sections = []
            outlineView.reloadData()
            return
        }

        let fm = FileManager.default
        allSections = BlogSettings.sections.map { dirName in
            let displayName: String
            switch dirName {
            case "posts":    displayName = "Post"
            case "research": displayName = "Research"
            case "data":     displayName = "Data"
            case "bergen":   displayName = "Bergen"
            default:         displayName = dirName.capitalized
            }

            guard let dir = BlogSettings.shared.directoryFor(section: dirName),
                  let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                return Section(name: displayName, dirName: dirName, posts: [])
            }

            let posts = contents
                .filter { $0.hasDirectoryPath }
                .compactMap { subdir -> BlogPost? in
                    let md = subdir.appendingPathComponent("index.md")
                    guard fm.fileExists(atPath: md.path) else { return nil }
                    return BlogPost(slug: subdir.lastPathComponent, path: md)
                }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

            return Section(name: displayName, dirName: dirName, posts: posts)
        }

        applyFilter()

        // Expand all sections
        for i in 0..<sections.count {
            outlineView.expandItem(sections[i].name)
        }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.lowercased()
        if q.isEmpty {
            sections = allSections
        } else {
            sections = allSections.map { sec in
                let filtered = sec.posts.filter {
                    $0.title.lowercased().contains(q) || $0.slug.lowercased().contains(q)
                }
                return Section(name: sec.name, dirName: sec.dirName, posts: filtered)
            }
        }
        outlineView.reloadData()
        // Expand all after reload
        for sec in sections {
            outlineView.expandItem(sec.name)
        }
    }

    // MARK: - Actions

    @objc private func itemClicked() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)
        if let post = item as? BlogPost {
            onPostSelected?(post)
        }
    }

    @objc private func handleRightClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: outlineView)
        let row = outlineView.row(at: point)
        guard row >= 0 else { return }

        let item = outlineView.item(atRow: row)

        if let post = item as? BlogPost {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let menu = NSMenu()
            let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteSelectedPost), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
            menu.popUp(positioning: nil, at: point, in: outlineView)
        }
    }

    @objc private func deleteSelectedPost() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        guard let post = outlineView.item(atRow: row) as? BlogPost else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Post"
        alert.informativeText = "Delete \"\(post.title)\"? This will remove the folder locally."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let postDir = post.path.deletingLastPathComponent()
        do {
            try FileManager.default.removeItem(at: postDir)
            refreshPosts()
            onPostDeleted?(post)
        } catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return sections.count
        }
        if let name = item as? String,
           let sec = sections.first(where: { $0.name == name }) {
            return sec.posts.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sections[index].name
        }
        if let name = item as? String,
           let sec = sections.first(where: { $0.name == name }) {
            return sec.posts[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is String
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is String
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {

        // Section header
        if let name = item as? String {
            let id = NSUserInterfaceItemIdentifier("SectionHeader")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = .systemFont(ofSize: 11, weight: .semibold)
                tf.textColor = .secondaryLabelColor
                tf.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(tf)
                cell.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = name.uppercased()
            return cell
        }

        // Post row
        if let post = item as? BlogPost {
            let id = NSUserInterfaceItemIdentifier("PostCell")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = id

                let titleField = NSTextField(labelWithString: "")
                titleField.font = .systemFont(ofSize: 12)
                titleField.textColor = .labelColor
                titleField.lineBreakMode = .byTruncatingTail
                titleField.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(titleField)
                cell.textField = titleField

                let dateField = NSTextField(labelWithString: "")
                dateField.font = .systemFont(ofSize: 10)
                dateField.textColor = .tertiaryLabelColor
                dateField.translatesAutoresizingMaskIntoConstraints = false
                dateField.tag = 100
                cell.addSubview(dateField)

                NSLayoutConstraint.activate([
                    titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                    dateField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    dateField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
                ])
            }

            cell.textField?.stringValue = post.title
            if let df = cell.viewWithTag(100) as? NSTextField {
                if let date = post.date {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy/MM/dd"
                    df.stringValue = f.string(from: date)
                } else {
                    df.stringValue = ""
                }
            }
            return cell
        }

        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // Allow selecting both section headers and posts
        return true
    }
}
