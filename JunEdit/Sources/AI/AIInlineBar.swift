import Cocoa
import QuartzCore

// MARK: - Cursor-style inline AI panel (polished)

class AIInlineBar: NSPanel {

    // ── UI pieces ────────────────────────────────────────────────
    private let card = NSView()
    private let glowBar = NSView()            // thin accent line at top
    private let inputContainer = NSView()
    private let iconView = NSImageView()
    private let promptField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let sendBtn = NSButton()
    private let spinner = NSProgressIndicator()
    private let divider = NSView()
    private let resultScroll = NSScrollView()
    private let resultText = NSTextView()
    private let actionBar = NSView()
    private let acceptBtn = HoverButton()
    private let rejectBtn = HoverButton()
    private let hintLabel = NSTextField(labelWithString: "")

    // ── Constraints we toggle ────────────────────────────────────
    private var cardHeight: NSLayoutConstraint!
    private var resultH: NSLayoutConstraint!
    private var actionH: NSLayoutConstraint!
    private var dividerH: NSLayoutConstraint!

    // ── State ────────────────────────────────────────────────────
    private var latestResult = ""
    private(set) var isGenerating = false
    var onSubmit: ((String) -> Void)?
    var onAccept: ((String) -> Void)?
    var onReject: (() -> Void)?

    // ── Palette ──────────────────────────────────────────────────
    private var dk: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private var colCardBg:      NSColor { dk ? NSColor(srgb: 0x1E1E22) : NSColor(srgb: 0xFFFFFF) }
    private var colCardBorder:  NSColor { dk ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.09) }
    private var colInputBg:     NSColor { dk ? NSColor(srgb: 0x141418) : NSColor(srgb: 0xF4F4F5) }
    private var colInputBorder: NSColor { dk ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.08) }
    private var colText:        NSColor { dk ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1) }
    private var colDim:         NSColor { dk ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.50, alpha: 1) }
    private var colAccent:      NSColor { NSColor(srgb: 0x7C6AEF) }   // Cursor purple
    private var colAccentSoft:  NSColor { NSColor(srgb: 0x7C6AEF).withAlphaComponent(dk ? 0.25 : 0.12) }
    private var colResultBg:    NSColor { dk ? NSColor(srgb: 0x111115) : NSColor(srgb: 0xF7F7F8) }
    private var colGreen:       NSColor { NSColor(srgb: 0x2EA043) }
    private var colSep:         NSColor { dk ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.06) }

    // ── Init ─────────────────────────────────────────────────────

    init(width: CGFloat = 540) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false          // we draw our own shadow
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = false

        buildCard(width)
        buildInputRow()
        buildDivider()
        buildResultArea()
        buildActionBar()
        layoutAll()
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Build UI
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildCard(_ w: CGFloat) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = colCardBg.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = colCardBorder.cgColor
        card.layer?.masksToBounds = false

        // Soft shadow
        card.shadow = NSShadow()
        card.layer?.shadowColor = NSColor.black.withAlphaComponent(dk ? 0.7 : 0.18).cgColor
        card.layer?.shadowOpacity = 1
        card.layer?.shadowRadius = 24
        card.layer?.shadowOffset = CGSize(width: 0, height: -6)

        card.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(card)

        // Accent glow line at top
        glowBar.wantsLayer = true
        glowBar.layer?.backgroundColor = colAccent.cgColor
        glowBar.layer?.cornerRadius = 1
        glowBar.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(glowBar)
    }

    private func buildInputRow() {
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = 10
        inputContainer.layer?.backgroundColor = colInputBg.cgColor
        inputContainer.layer?.borderWidth = 1
        inputContainer.layer?.borderColor = colInputBorder.cgColor
        inputContainer.translatesAutoresizingMaskIntoConstraints = false

        // SF Symbol icon
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let img = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            iconView.image = img
            iconView.contentTintColor = colAccent
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Prompt
        promptField.placeholderAttributedString = NSAttributedString(
            string: "Describe your edit...",
            attributes: [.foregroundColor: colDim, .font: NSFont.systemFont(ofSize: 13)]
        )
        promptField.font = NSFont.systemFont(ofSize: 13)
        promptField.isBordered = false
        promptField.focusRingType = .none
        promptField.drawsBackground = false
        promptField.textColor = colText
        promptField.target = self
        promptField.action = #selector(submit)
        promptField.translatesAutoresizingMaskIntoConstraints = false

        // Send button
        if let img = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) {
            sendBtn.image = img
        }
        sendBtn.contentTintColor = colAccent
        sendBtn.isBordered = false
        sendBtn.target = self
        sendBtn.action = #selector(submit)
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        // Spinner (replaces send btn during generation)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        // Status label ("Generating..." text)
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = colAccent
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        inputContainer.addSubview(iconView)
        inputContainer.addSubview(promptField)
        inputContainer.addSubview(sendBtn)
        inputContainer.addSubview(spinner)
        inputContainer.addSubview(statusLabel)
    }

    private func buildDivider() {
        divider.wantsLayer = true
        divider.layer?.backgroundColor = colSep.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildResultArea() {
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.borderType = .noBorder
        resultScroll.drawsBackground = false
        resultScroll.translatesAutoresizingMaskIntoConstraints = false

        resultText.isEditable = false
        resultText.isSelectable = true
        resultText.drawsBackground = true
        resultText.backgroundColor = colResultBg
        resultText.textColor = colText
        resultText.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        resultText.textContainerInset = NSSize(width: 12, height: 10)
        resultText.isVerticallyResizable = true
        resultText.isHorizontallyResizable = false
        resultText.autoresizingMask = [.width]
        resultText.textContainer?.widthTracksTextView = true
        resultText.wantsLayer = true
        resultText.layer?.cornerRadius = 8

        resultScroll.documentView = resultText
    }

    private func buildActionBar() {
        actionBar.translatesAutoresizingMaskIntoConstraints = false

        // Accept
        styleAction(acceptBtn, label: "Accept", symbol: "checkmark", color: colGreen, bgColor: colGreen.withAlphaComponent(dk ? 0.15 : 0.08))
        acceptBtn.target = self
        acceptBtn.action = #selector(doAccept)

        // Reject
        styleAction(rejectBtn, label: "Reject", symbol: "xmark", color: colDim, bgColor: colDim.withAlphaComponent(dk ? 0.12 : 0.06))
        rejectBtn.target = self
        rejectBtn.action = #selector(doReject)
        rejectBtn.keyEquivalent = "\u{1b}"

        // Hint
        hintLabel.stringValue = "\u{23CE} follow up   \u{238B} dismiss"
        hintLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = colDim.withAlphaComponent(0.6)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        acceptBtn.translatesAutoresizingMaskIntoConstraints = false
        rejectBtn.translatesAutoresizingMaskIntoConstraints = false

        actionBar.addSubview(hintLabel)
        actionBar.addSubview(rejectBtn)
        actionBar.addSubview(acceptBtn)
    }

    private func styleAction(_ btn: HoverButton, label: String, symbol: String, color: NSColor, bgColor: NSColor) {
        btn.wantsLayer = true
        btn.isBordered = false
        btn.layer?.cornerRadius = 7
        btn.layer?.backgroundColor = bgColor.cgColor
        btn.hoverBgColor = color.withAlphaComponent(dk ? 0.25 : 0.14)
        btn.normalBgColor = bgColor

        let attr = NSMutableAttributedString()
        let symConf = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symConf) {
            let a = NSTextAttachment()
            a.image = img
            attr.append(NSAttributedString(attachment: a))
        }
        attr.append(NSAttributedString(string: " \(label)", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
        ]))
        attr.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: attr.length))
        btn.attributedTitle = attr
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Constraints
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func layoutAll() {
        card.addSubview(inputContainer)
        card.addSubview(divider)
        card.addSubview(resultScroll)
        card.addSubview(actionBar)

        cardHeight = card.heightAnchor.constraint(equalToConstant: 48)
        resultH    = resultScroll.heightAnchor.constraint(equalToConstant: 0)
        actionH    = actionBar.heightAnchor.constraint(equalToConstant: 0)
        dividerH   = divider.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Card fills window
            card.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -8),
            card.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor, constant: -8),
            cardHeight,

            // Glow bar
            glowBar.topAnchor.constraint(equalTo: card.topAnchor),
            glowBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            glowBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            glowBar.heightAnchor.constraint(equalToConstant: 2),

            // Input container
            inputContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            inputContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            inputContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            inputContainer.heightAnchor.constraint(equalToConstant: 34),

            // Icon
            iconView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            // Prompt
            promptField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            promptField.trailingAnchor.constraint(equalTo: sendBtn.leadingAnchor, constant: -4),
            promptField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),

            // Status label (during generation)
            statusLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),

            // Send
            sendBtn.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -6),
            sendBtn.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 24),
            sendBtn.heightAnchor.constraint(equalToConstant: 24),

            // Spinner
            spinner.centerXAnchor.constraint(equalTo: sendBtn.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendBtn.centerYAnchor),

            // Divider
            divider.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 6),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            dividerH,

            // Result
            resultScroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 0),
            resultScroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            resultScroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            resultH,

            // Action bar
            actionBar.topAnchor.constraint(equalTo: resultScroll.bottomAnchor, constant: 0),
            actionBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            actionBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            actionH,

            // Action contents
            hintLabel.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 4),
            hintLabel.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),

            rejectBtn.trailingAnchor.constraint(equalTo: acceptBtn.leadingAnchor, constant: -8),
            rejectBtn.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            rejectBtn.heightAnchor.constraint(equalToConstant: 26),
            rejectBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            acceptBtn.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -2),
            acceptBtn.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            acceptBtn.heightAnchor.constraint(equalToConstant: 26),
            acceptBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Show / Dismiss
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func showBelow(screenPoint: NSPoint, parentWindow: NSWindow?) {
        let barW: CGFloat = 540
        let barH: CGFloat = 48 + 16  // card + shadow padding
        let origin = NSPoint(x: screenPoint.x - 16, y: screenPoint.y - barH - 2)
        setFrame(NSRect(x: origin.x, y: origin.y, width: barW, height: barH), display: true)

        if let parent = parentWindow {
            parent.addChildWindow(self, ordered: .above)
        }
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.makeKey()
            self?.makeFirstResponder(self?.promptField)
        }

        // Entrance animation
        card.alphaValue = 0
        card.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -4).scaledBy(x: 0.98, y: 0.98))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().alphaValue = 1
            card.layer?.setAffineTransform(.identity)
        }

        // Glow bar shimmer
        animateGlow()
    }

    private func animateGlow() {
        glowBar.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowBar.animator().alphaValue = 1.0
        }) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self?.glowBar.animator().alphaValue = 0.3
            }) { [weak self] in
                if self?.isVisible == true { self?.animateGlow() }
            }
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            card.animator().alphaValue = 0
            card.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -3).scaledBy(x: 0.98, y: 0.98))
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.parent?.removeChildWindow(self)
            self.orderOut(nil)
        })
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Loading / Result
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func showLoading() {
        isGenerating = true
        promptField.isHidden = true
        statusLabel.stringValue = "Generating..."
        statusLabel.isHidden = false
        sendBtn.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)

        // Accent border glow
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            inputContainer.layer?.borderColor = colAccent.withAlphaComponent(0.6).cgColor
            inputContainer.layer?.borderWidth = 1.5
        }
    }

    func showResult(_ text: String) {
        isGenerating = false
        latestResult = text

        // Restore input
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        sendBtn.isHidden = false
        promptField.isHidden = false
        promptField.isEditable = true
        promptField.alphaValue = 1.0
        promptField.stringValue = ""
        promptField.placeholderAttributedString = NSAttributedString(
            string: "Follow up...",
            attributes: [.foregroundColor: colDim, .font: NSFont.systemFont(ofSize: 13)]
        )
        statusLabel.isHidden = true
        inputContainer.layer?.borderColor = colInputBorder.cgColor
        inputContainer.layer?.borderWidth = 1

        // Populate result
        resultText.string = text

        // Calculate sizes
        resultText.layoutManager?.ensureLayout(for: resultText.textContainer!)
        let textH = resultText.layoutManager?.usedRect(for: resultText.textContainer!).height ?? 40
        let scrollH = min(textH + 24, 240)

        // Animate expansion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true

            dividerH.constant = 0.5
            resultH.constant = scrollH
            actionH.constant = 36

            let totalCard: CGFloat = 8 + 34 + 6 + 0.5 + scrollH + 36 + 8
            cardHeight.constant = totalCard

            var f = frame
            let totalWindow = totalCard + 16
            let bottom = f.origin.y
            f.size.height = totalWindow
            f.origin.y = bottom + (frame.height - totalWindow)
            setFrame(f, display: true)

            card.layoutSubtreeIfNeeded()
        }

        makeFirstResponder(promptField)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func submit() {
        let text = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        showLoading()
        onSubmit?(text)
    }

    @objc private func doAccept() { onAccept?(latestResult) }
    @objc private func doReject() { onReject?() }
}

// MARK: - HoverButton (pill with hover effect)

class HoverButton: NSButton {
    var normalBgColor: NSColor = .clear
    var hoverBgColor: NSColor = .clear

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            layer?.backgroundColor = hoverBgColor.cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            layer?.backgroundColor = normalBgColor.cgColor
        }
    }
}

// MARK: - NSColor convenience

private extension NSColor {
    /// Create from hex integer, e.g. NSColor(srgb: 0x1E1E22)
    convenience init(srgb hex: Int) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
