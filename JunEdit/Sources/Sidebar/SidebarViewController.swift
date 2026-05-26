import Cocoa

class SidebarViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private var allPosts: [BlogPost] = []
    private var filteredPosts: [BlogPost] = []

    var onPostSelected: ((BlogPost) -> Void)?

    override func loadView() {
        // Native macOS sidebar vibrancy
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .sidebar
        effectView.state = .followsWindowActiveState
        view = effectView

        setupSearchField()
        setupTableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshPosts()
    }

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

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteCol"))
        column.title = ""
        column.isEditable = false
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 40
        tableView.style = .sourceList
        tableView.selectionHighlightStyle = .sourceList
        tableView.target = self
        tableView.action = #selector(noteClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2 // right click
        tableView.addGestureRecognizer(rightClick)

        scrollView.documentView = tableView
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

    func refreshPosts() {
        guard let postsDir = BlogSettings.shared.postsDirectory else {
            NSLog("JunEdit: No posts directory configured")
            allPosts = []
            filteredPosts = []
            tableView.reloadData()
            return
        }

        NSLog("JunEdit: Looking for posts in \(postsDir.path)")

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: postsDir, includingPropertiesForKeys: nil) else {
            NSLog("JunEdit: Cannot read directory \(postsDir.path)")
            allPosts = []
            filteredPosts = []
            tableView.reloadData()
            return
        }

        let dirs = contents.filter { $0.hasDirectoryPath }
        NSLog("JunEdit: Found \(dirs.count) subdirectories")

        allPosts = dirs.compactMap { (dir: URL) -> BlogPost? in
            let md = dir.appendingPathComponent("index.md")
            let exists = fm.fileExists(atPath: md.path)
            NSLog("JunEdit: \(dir.lastPathComponent)/index.md exists: \(exists)")
            guard exists else { return nil }
            return BlogPost(slug: dir.lastPathComponent, path: md)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        NSLog("JunEdit: Loaded \(allPosts.count) posts")
        applyFilter()
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.lowercased()
        filteredPosts = q.isEmpty ? allPosts : allPosts.filter {
            $0.title.lowercased().contains(q) || $0.slug.lowercased().contains(q)
        }
        tableView.reloadData()
    }

    @objc private func noteClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredPosts.count else { return }
        onPostSelected?(filteredPosts[row])
    }

    var onPostDeleted: ((BlogPost) -> Void)?

    @objc private func handleRightClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: tableView)
        let row = tableView.row(at: point)
        guard row >= 0, row < filteredPosts.count else { return }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteSelectedPost), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        menu.popUp(positioning: nil, at: point, in: tableView)
    }

    @objc private func deleteSelectedPost() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredPosts.count else { return }
        let post = filteredPosts[row]

        // Confirm deletion
        let alert = NSAlert()
        alert.messageText = "Delete Post"
        alert.informativeText = "Delete \"\(post.title)\"? This will remove the post folder locally."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Delete the post directory locally only
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

extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredPosts.count }
}

extension SidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let post = filteredPosts[row]
        let identifier = NSUserInterfaceItemIdentifier("NoteCell")

        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            // Title
            let titleField = NSTextField(labelWithString: "")
            titleField.font = .systemFont(ofSize: 12)
            titleField.textColor = .labelColor
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleField)
            cell.textField = titleField

            // Date below title
            let dateField = NSTextField(labelWithString: "")
            dateField.font = .systemFont(ofSize: 10)
            dateField.textColor = .tertiaryLabelColor
            dateField.translatesAutoresizingMaskIntoConstraints = false
            dateField.tag = 100
            cell.addSubview(dateField)

            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),
                dateField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                dateField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            ])
        }

        cell.textField?.stringValue = post.title
        if let df = cell.viewWithTag(100) as? NSTextField {
            if let date = post.date {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd HH:mm"
                df.stringValue = f.string(from: date)
            } else {
                df.stringValue = ""
            }
        }
        return cell
    }
}
