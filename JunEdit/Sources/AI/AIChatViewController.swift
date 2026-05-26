import Cocoa

/// Side panel chat view for conversational AI interaction
class AIChatViewController: NSViewController {

    private let chatScroll = NSScrollView()
    private let chatStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private var onInsertToEditor: ((String) -> Void)?

    /// Provide the current document content for context
    var documentContext: (() -> String)?

    func setInsertHandler(_ handler: @escaping (String) -> Void) {
        onInsertToEditor = handler
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Chat messages scroll area
        chatStack.orientation = .vertical
        chatStack.alignment = .leading
        chatStack.spacing = 8
        chatStack.translatesAutoresizingMaskIntoConstraints = false

        // Clip view
        chatScroll.documentView = chatStack
        chatScroll.hasVerticalScroller = true
        chatScroll.drawsBackground = false
        chatScroll.translatesAutoresizingMaskIntoConstraints = false

        // Input area
        inputField.placeholderString = "Ask AI..."
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.focusRingType = .none
        inputField.target = self
        inputField.action = #selector(send)

        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.target = self
        sendButton.action = #selector(send)

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 6
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(chatScroll)
        container.addSubview(inputRow)

        NSLayoutConstraint.activate([
            chatScroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            chatScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            chatScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            chatScroll.bottomAnchor.constraint(equalTo: inputRow.topAnchor, constant: -8),

            inputRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            inputRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            inputRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            inputRow.heightAnchor.constraint(equalToConstant: 28),

            inputField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        // Make chatStack fill the scroll width
        if let docView = chatScroll.documentView {
            chatStack.widthAnchor.constraint(equalTo: docView.widthAnchor).isActive = true
        }

        view = container
    }

    @objc private func send() {
        let prompt = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputField.stringValue = ""

        addBubble(text: prompt, isUser: true)

        let context = documentContext?()
        let responseBubble = addBubble(text: "", isUser: false)

        inputField.isEnabled = false
        sendButton.isEnabled = false

        AIRunner.shared.run(prompt: prompt, context: context, onOutput: { [weak responseBubble] chunk in
            guard let bubble = responseBubble else { return }
            bubble.stringValue += chunk
        }, onComplete: { [weak self] error in
            self?.inputField.isEnabled = true
            self?.sendButton.isEnabled = true
            if let error = error {
                self?.addBubble(text: "Error: \(error.localizedDescription)", isUser: false)
            }
            self?.scrollToBottom()
        })
    }

    @discardableResult
    private func addBubble(text: String, isUser: Bool) -> NSTextField {
        let bubble = NSTextField(wrappingLabelWithString: text)
        bubble.font = NSFont.systemFont(ofSize: 13)
        bubble.isSelectable = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true

        if isUser {
            bubble.textColor = .secondaryLabelColor
            bubble.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.1).cgColor
        } else {
            bubble.textColor = .labelColor
            bubble.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        }
        bubble.layer?.cornerRadius = 6

        // Copy button for AI responses
        if !isUser {
            let wrapper = NSStackView()
            wrapper.orientation = .vertical
            wrapper.alignment = .leading
            wrapper.spacing = 2
            wrapper.translatesAutoresizingMaskIntoConstraints = false

            let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyBubble(_:)))
            copyBtn.bezelStyle = .accessoryBarAction
            copyBtn.font = NSFont.systemFont(ofSize: 10)
            copyBtn.tag = chatStack.arrangedSubviews.count

            let insertBtn = NSButton(title: "Insert", target: self, action: #selector(insertBubble(_:)))
            insertBtn.bezelStyle = .accessoryBarAction
            insertBtn.font = NSFont.systemFont(ofSize: 10)
            insertBtn.tag = chatStack.arrangedSubviews.count

            let btnRow = NSStackView(views: [copyBtn, insertBtn])
            btnRow.orientation = .horizontal
            btnRow.spacing = 4

            wrapper.addArrangedSubview(bubble)
            wrapper.addArrangedSubview(btnRow)
            chatStack.addArrangedSubview(wrapper)
        } else {
            chatStack.addArrangedSubview(bubble)
        }

        scrollToBottom()
        return bubble
    }

    @objc private func copyBubble(_ sender: NSButton) {
        if let text = findBubbleText(tag: sender.tag) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc private func insertBubble(_ sender: NSButton) {
        if let text = findBubbleText(tag: sender.tag) {
            onInsertToEditor?(text)
        }
    }

    private func findBubbleText(tag: Int) -> String? {
        guard tag < chatStack.arrangedSubviews.count else { return nil }
        let view = chatStack.arrangedSubviews[tag]
        if let stack = view as? NSStackView, let tf = stack.arrangedSubviews.first as? NSTextField {
            return tf.stringValue
        }
        return (view as? NSTextField)?.stringValue
    }

    private func scrollToBottom() {
        DispatchQueue.main.async {
            if let docView = self.chatScroll.documentView {
                let y = docView.frame.height - self.chatScroll.contentSize.height
                self.chatScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            }
        }
    }
}
