//
//  AddAccountWindowController.swift
//  FastSM (macOS)
//
//  Sheet for adding an account. Mastodon: enter an instance, then authorize in
//  the browser. Bluesky: enter a handle and an app password.
//

import AppKit
import FastSMCore

@MainActor
final class AddAccountWindowController: NSWindowController {
    private let services: AppServices
    private weak var anchorProvider: PresentationAnchorProviding?

    var onComplete: (() -> Void)?

    private let platformPopup = NSPopUpButton()
    private let field1 = NSTextField()       // instance (Mastodon) / handle (Bluesky)
    private let field2 = NSSecureTextField() // app password (Bluesky only)
    private let field2Label = NSTextField(labelWithString: "App password:")
    private let field1Label = NSTextField(labelWithString: "Server:")
    private let progress = NSProgressIndicator()
    private let addButton = NSButton()

    init(services: AppServices, anchorProvider: PresentationAnchorProviding) {
        self.services = services
        self.anchorProvider = anchorProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Add Account"
        buildUI()
        updateForPlatform()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, onDismiss: @escaping () -> Void) {
        parent.beginSheet(window!) { _ in onDismiss() }
        window?.makeFirstResponder(field1)
    }

    private var selectedPlatform: Platform {
        platformPopup.indexOfSelectedItem == 0 ? .mastodon : .bluesky
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        platformPopup.addItems(withTitles: ["Mastodon", "Bluesky"])
        platformPopup.target = self
        platformPopup.action = #selector(platformChanged(_:))
        platformPopup.setAccessibilityLabel("Platform")
        stack.addArrangedSubview(labeledRow(NSTextField(labelWithString: "Platform:"), platformPopup))

        field1.setAccessibilityLabel("Server or handle")
        field1.translatesAutoresizingMaskIntoConstraints = false
        field1.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(labeledRow(field1Label, field1))

        field2.setAccessibilityLabel("App password")
        field2.translatesAutoresizingMaskIntoConstraints = false
        field2.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(labeledRow(field2Label, field2))

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        bottom.addArrangedSubview(progress)
        bottom.addArrangedSubview(NSView())

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        bottom.addArrangedSubview(cancel)

        addButton.title = "Add"
        addButton.target = self
        addButton.action = #selector(add(_:))
        addButton.keyEquivalent = "\r"
        addButton.bezelStyle = .rounded
        bottom.addArrangedSubview(addButton)

        bottom.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(bottom)
        bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
    }

    private func labeledRow(_ label: NSTextField, _ control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true
        label.alignment = .right
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    @objc private func platformChanged(_ sender: Any?) { updateForPlatform() }

    private func updateForPlatform() {
        switch selectedPlatform {
        case .mastodon:
            field1Label.stringValue = "Server:"
            field1.placeholderString = "mastodon.social"
            field2Label.isHidden = true
            field2.isHidden = true
        case .bluesky:
            field1Label.stringValue = "Handle:"
            field1.placeholderString = "you.bsky.social"
            field2Label.isHidden = false
            field2.isHidden = false
            field2.placeholderString = "xxxx-xxxx-xxxx-xxxx"
        }
    }

    private func setBusy(_ busy: Bool) {
        addButton.isEnabled = !busy
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    @objc private func cancel(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!)
    }

    @objc private func add(_ sender: Any?) {
        let input = field1.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        setBusy(true)

        Task {
            do {
                switch selectedPlatform {
                case .mastodon:
                    guard let anchorProvider else { throw PlatformError.message("No window available for sign-in.") }
                    let (credentials, me) = try await MastodonAuth.signIn(instance: input, anchorProvider: anchorProvider, clientName: "FastSM for Mac")
                    services.accountStore.add(MastodonAccount(credentials: credentials, me: me))
                case .bluesky:
                    let account = try await BlueskyAccount.signIn(identifier: input, appPassword: field2.stringValue)
                    services.accountStore.add(account)
                }
                services.sound.play(.postSent)
                onComplete?()
                window?.sheetParent?.endSheet(window!)
            } catch {
                services.sound.play(.error)
                setBusy(false)
                let alert = NSAlert()
                alert.messageText = "Couldn't add account"
                alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let window { alert.beginSheetModal(for: window, completionHandler: nil) }
            }
        }
    }
}
