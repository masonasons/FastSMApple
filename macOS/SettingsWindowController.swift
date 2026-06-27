//
//  SettingsWindowController.swift
//  FastSM (macOS)
//
//  The Settings window, organized into tabs that mirror FastSM's options dialog
//  (General, Timelines, Audio, Advanced, Confirmation) via NSTabViewController's
//  toolbar style. Only the categories we currently have settings for are shown.
//

import AppKit
import FastSMCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore

    private let fetchPagesStepper = NSStepper()
    private let fetchPagesValueLabel = NSTextField(labelWithString: "")
    private let cacheLimitStepper = NSStepper()
    private let cacheLimitValueLabel = NSTextField(labelWithString: "")

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Settings"
        window.isReleasedWhenClosed = false

        let tabController = NSTabViewController()
        tabController.tabStyle = .toolbar
        tabController.addTabViewItem(makeTab("General", symbol: "gearshape") { self.buildGeneral($0) })
        tabController.addTabViewItem(makeTab("Timelines", symbol: "list.bullet") { self.buildTimelines($0) })
        tabController.addTabViewItem(makeTab("Audio", symbol: "speaker.wave.2") { self.buildAudio($0) })
        tabController.addTabViewItem(makeSpeechTab())
        tabController.addTabViewItem(makeMovementTab())
        tabController.addTabViewItem(makeTab("Advanced", symbol: "wrench.and.screwdriver") { self.buildAdvanced($0) })
        tabController.addTabViewItem(makeTab("Confirmation", symbol: "checkmark.shield") { self.buildConfirmation($0) })
        window.contentViewController = tabController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Scaffolding

    private func makeSpeechTab() -> NSTabViewItem {
        let item = NSTabViewItem(viewController: SpeechSettingsViewController(settings: settings))
        item.label = "Speech"
        item.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Speech")
        return item
    }

    private func makeMovementTab() -> NSTabViewItem {
        let item = NSTabViewItem(viewController: MovementSettingsViewController(settings: settings))
        item.label = "Movement"
        item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Movement")
        return item
    }

    private func makeTab(_ title: String, symbol: String, _ build: (NSStackView) -> Void) -> NSTabViewItem {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 480),
        ])
        build(stack)

        let viewController = NSViewController()
        viewController.view = container
        let item = NSTabViewItem(viewController: viewController)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func detail(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return label
    }

    private func checkbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: action)
        box.state = on ? .on : .off
        return box
    }

    private func stepperRow(label: String, stepper: NSStepper, valueLabel: NSTextField,
                            range: ClosedRange<Int>, increment: Int, value: Int, action: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(NSTextField(labelWithString: label))
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = Double(increment)
        stepper.integerValue = value
        stepper.target = self
        stepper.action = action
        stepper.setAccessibilityLabel(label)
        valueLabel.stringValue = "\(value)"
        row.addArrangedSubview(stepper)
        row.addArrangedSubview(valueLabel)
        return row
    }

    // MARK: Tabs

    private func buildGeneral(_ stack: NSStackView) {
        stack.addArrangedSubview(checkbox(
            "Remove emojis and other unicode characters from post text",
            on: settings.settings.demojify, action: #selector(toggleDemojify(_:))))
        stack.addArrangedSubview(checkbox(
            "Use ⌘Return to send posts (instead of Return)",
            on: !settings.settings.enterToSend, action: #selector(toggleCommandReturn(_:))))
    }

    private let autoRefreshPopup = NSPopUpButton()

    private func buildTimelines(_ stack: NSStackView) {
        stack.addArrangedSubview(stepperRow(
            label: "Maximum items to cache per timeline:",
            stepper: cacheLimitStepper, valueLabel: cacheLimitValueLabel,
            range: AppSettings.cacheLimitRange, increment: 250,
            value: settings.settings.cacheLimit, action: #selector(changeCacheLimit(_:))))
        stack.addArrangedSubview(detail("Posts kept on disk per timeline for instant startup."))

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(NSTextField(labelWithString: "Auto-refresh:"))
        for seconds in AppSettings.autoRefreshOptions {
            autoRefreshPopup.addItem(withTitle: Self.autoRefreshLabel(seconds))
            autoRefreshPopup.lastItem?.tag = seconds
        }
        autoRefreshPopup.selectItem(withTag: settings.settings.autoRefreshSeconds)
        autoRefreshPopup.target = self
        autoRefreshPopup.action = #selector(changeAutoRefresh(_:))
        autoRefreshPopup.setAccessibilityLabel("Auto-refresh interval")
        row.addArrangedSubview(autoRefreshPopup)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(detail("Automatically check timelines for new posts. New posts play that timeline's sound."))

        stack.addArrangedSubview(checkbox(
            "Sync home timeline position with Mastodon (Mastodon only)",
            on: settings.settings.syncHomePosition, action: #selector(toggleSyncHomePosition(_:))))

        stack.addArrangedSubview(checkbox(
            "Stream timelines in real time (Mastodon only)",
            on: settings.settings.streamingEnabled, action: #selector(toggleStreaming(_:))))
        stack.addArrangedSubview(detail("Receive new posts/mentions live over a streaming connection."))

        stack.addArrangedSubview(checkbox(
            "Go Back remembers every step, not just jumps",
            on: settings.settings.recordEveryNavStep, action: #selector(toggleRecordEveryNavStep(_:))))
        stack.addArrangedSubview(detail("⌘Z steps back through navigation history. When off, only jumps (movement units, big moves) are recorded."))
    }

    @objc private func toggleSyncHomePosition(_ sender: NSButton) {
        settings.update { $0.syncHomePosition = (sender.state == .on) }
    }

    @objc private func toggleStreaming(_ sender: NSButton) {
        settings.update { $0.streamingEnabled = (sender.state == .on) }
    }

    @objc private func toggleRecordEveryNavStep(_ sender: NSButton) {
        settings.update { $0.recordEveryNavStep = (sender.state == .on) }
    }

    static func autoRefreshLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Off"
        case 30: return "Every 30 seconds"
        case 60: return "Every minute"
        case 120: return "Every 2 minutes"
        case 300: return "Every 5 minutes"
        default: return "Every \(seconds)s"
        }
    }

    @objc private func changeAutoRefresh(_ sender: NSPopUpButton) {
        settings.update { $0.autoRefreshSeconds = sender.selectedTag() }
    }

    private let soundpackPopup = NSPopUpButton()

    private func buildAudio(_ stack: NSStackView) {
        stack.addArrangedSubview(checkbox(
            "Play sounds", on: settings.settings.soundsEnabled, action: #selector(toggleSounds(_:))))

        let packRow = NSStackView()
        packRow.orientation = .horizontal
        packRow.spacing = 8
        packRow.addArrangedSubview(NSTextField(labelWithString: "Soundpack:"))
        let packs = AppServices.availableSoundpacks()
        soundpackPopup.addItems(withTitles: packs)
        soundpackPopup.selectItem(withTitle: packs.contains(settings.settings.soundpack) ? settings.settings.soundpack : AppSettings.defaultSoundpackName)
        soundpackPopup.target = self
        soundpackPopup.action = #selector(changeSoundpack(_:))
        soundpackPopup.setAccessibilityLabel("Soundpack")
        packRow.addArrangedSubview(soundpackPopup)
        stack.addArrangedSubview(packRow)

        stack.addArrangedSubview(detail("A Default soundpack is built in. To add your own, paste a soundpack folder into the soundpacks folder, then pick it here."))
        let openButton = NSButton(title: "Open Soundpacks Folder in Finder", target: self, action: #selector(openSoundpacksFolder(_:)))
        openButton.bezelStyle = .rounded
        stack.addArrangedSubview(openButton)
    }

    @objc private func changeSoundpack(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        settings.update { $0.soundpack = name }
    }

    @objc private func openSoundpacksFolder(_ sender: Any?) {
        if let dir = AppServices.soundpacksDirectory() {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
    }

    private func buildAdvanced(_ stack: NSStackView) {
        stack.addArrangedSubview(stepperRow(
            label: "Number of API calls to make when loading timelines (1-10):",
            stepper: fetchPagesStepper, valueLabel: fetchPagesValueLabel,
            range: AppSettings.fetchPagesRange, increment: 1,
            value: settings.settings.fetchPages, action: #selector(changeFetchPages(_:))))
        stack.addArrangedSubview(detail("Each call fetches about 40 posts. Applies to refresh and scrollback."))
    }

    private func buildConfirmation(_ stack: NSStackView) {
        let header = NSTextField(labelWithString: "Show confirmation dialogs for the following actions:")
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(checkbox("Boosting", on: settings.settings.confirmBoost, action: #selector(toggleConfirmBoost(_:))))
        stack.addArrangedSubview(checkbox("Favoriting", on: settings.settings.confirmFavorite, action: #selector(toggleConfirmFavorite(_:))))
        stack.addArrangedSubview(checkbox("Clearing a timeline", on: settings.settings.confirmClearTimeline, action: #selector(toggleConfirmClear(_:))))
    }

    // MARK: Actions

    @objc private func toggleSounds(_ sender: NSButton) { settings.update { $0.soundsEnabled = sender.state == .on } }
    @objc private func toggleDemojify(_ sender: NSButton) { settings.update { $0.demojify = sender.state == .on } }
    @objc private func toggleConfirmBoost(_ sender: NSButton) { settings.update { $0.confirmBoost = sender.state == .on } }
    @objc private func toggleConfirmFavorite(_ sender: NSButton) { settings.update { $0.confirmFavorite = sender.state == .on } }
    @objc private func toggleConfirmClear(_ sender: NSButton) { settings.update { $0.confirmClearTimeline = sender.state == .on } }

    // Checked = ⌘Return sends (enterToSend == false).
    @objc private func toggleCommandReturn(_ sender: NSButton) { settings.update { $0.enterToSend = sender.state == .off } }

    @objc private func changeFetchPages(_ sender: NSStepper) {
        fetchPagesValueLabel.stringValue = "\(sender.integerValue)"
        settings.update { $0.fetchPages = sender.integerValue }
    }

    @objc private func changeCacheLimit(_ sender: NSStepper) {
        cacheLimitValueLabel.stringValue = "\(sender.integerValue)"
        settings.update { $0.cacheLimit = sender.integerValue }
    }
}
