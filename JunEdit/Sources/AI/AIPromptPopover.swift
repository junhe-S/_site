import Cocoa

/// A small popover with a text field for entering AI prompts
class AIPromptPopover: NSPopover {
    private let promptField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var onSubmit: ((String) -> Void)?

    init(placeholder: String, onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        super.init()

        behavior = .transient
        contentSize = NSSize(width: 400, height: 44)

        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))

        // Prompt field
        promptField.placeholderString = placeholder
        promptField.font = NSFont.systemFont(ofSize: 13)
        promptField.translatesAutoresizingMaskIntoConstraints = false
        promptField.focusRingType = .none
        promptField.target = self
        promptField.action = #selector(submit)
        container.addSubview(promptField)

        // Status label (shows "Thinking..." while running)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            promptField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            promptField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            promptField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
        ])

        vc.view = container
        contentViewController = vc
    }

    required init?(coder: NSCoder) { fatalError() }

    func showStatus(_ text: String) {
        statusLabel.stringValue = text
        // Expand to show status
        if !text.isEmpty {
            contentSize = NSSize(width: 400, height: 64)
        }
    }

    @objc private func submit() {
        let text = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        promptField.isEnabled = false
        showStatus("AI thinking...")
        onSubmit?(text)
    }
}
