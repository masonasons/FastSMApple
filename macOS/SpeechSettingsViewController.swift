//
//  SpeechSettingsViewController.swift
//  FastSM (macOS)
//
//  Settings → Speech: choose what VoiceOver reads for posts and users. A table
//  of checkable fields; toggle to include/exclude, Option+Up/Down (or the
//  buttons) to reorder.
//

import AppKit
import FastSMCore

/// NSTableView that turns Option+Up / Option+Down into reorder commands and
/// Space into a toggle of the selected row.
final class SpeechTableView: NSTableView {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onToggle: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let option = event.modifierFlags.contains(.option)
        if option, event.keyCode == 126 { onMoveUp?(); return }   // up
        if option, event.keyCode == 125 { onMoveDown?(); return } // down
        if event.keyCode == 49 { onToggle?(); return }            // space
        super.keyDown(with: event)
    }
}

@MainActor
final class SpeechSettingsViewController: NSViewController {
    private let settings: SettingsStore
    private enum Mode: Int { case post, user }
    private var mode: Mode = .post

    private let segmented = NSSegmentedControl(labels: ["Posts", "Users"],
                                               trackingMode: .selectOne, target: nil, action: nil)
    private let tableView = SpeechTableView()
    private let cellID = NSUserInterfaceItemIdentifier("SpeechCell")

    private var statusItems: [SpeechItem<StatusSpeechField>]
    private var userItems: [SpeechItem<UserSpeechField>]

    init(settings: SettingsStore) {
        self.settings = settings
        self.statusItems = settings.settings.speech.status
        self.userItems = settings.settings.speech.user
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView()

        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(changeMode(_:))
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.setAccessibilityLabel("Configure speech for")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
        column.title = "Spoken fields"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.setAccessibilityLabel("Spoken fields, in order")
        tableView.onMoveUp = { [weak self] in self?.moveSelected(by: -1) }
        tableView.onMoveDown = { [weak self] in self?.moveSelected(by: 1) }
        tableView.onToggle = { [weak self] in self?.toggleSelected() }
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let upButton = NSButton(title: "Move Up", target: self, action: #selector(moveItemUp(_:)))
        let downButton = NSButton(title: "Move Down", target: self, action: #selector(moveItemDown(_:)))
        let buttonRow = NSStackView(views: [upButton, downButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "Press Space (or click) to toggle a field on/off. Reorder with Option+Up / Option+Down or the buttons.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(segmented)
        container.addSubview(scroll)
        container.addSubview(buttonRow)
        container.addSubview(hint)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 480),
            segmented.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            segmented.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),

            scroll.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scroll.heightAnchor.constraint(equalToConstant: 300),

            buttonRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),

            hint.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if tableView.selectedRow < 0, numberOfRows() > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func numberOfRows() -> Int { mode == .post ? statusItems.count : userItems.count }

    private func fieldName(_ row: Int) -> String {
        mode == .post ? statusItems[row].field.displayName : userItems[row].field.displayName
    }

    private func isEnabled(_ row: Int) -> Bool {
        mode == .post ? statusItems[row].enabled : userItems[row].enabled
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .post
        tableView.reloadData()
        if numberOfRows() > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        toggle(row: row)
    }

    private func toggleSelected() { toggle(row: tableView.selectedRow) }

    private func toggle(row: Int) {
        guard row >= 0, row < numberOfRows() else { return }
        let newValue: Bool
        if mode == .post { statusItems[row].enabled.toggle(); newValue = statusItems[row].enabled }
        else { userItems[row].enabled.toggle(); newValue = userItems[row].enabled }
        persist()
        if let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
            configure(rowView, at: row)
        }
        announce(newValue ? "checked" : "unchecked")
    }

    /// Speak the new state immediately (VoiceOver), since the row's value changed
    /// under the cursor.
    private func announce(_ message: String) {
        guard let element = view.window ?? NSApp.mainWindow else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc private func moveItemUp(_ sender: Any?) { moveSelected(by: -1) }
    @objc private func moveItemDown(_ sender: Any?) { moveSelected(by: 1) }

    private func moveSelected(by delta: Int) {
        let row = tableView.selectedRow
        let target = row + delta
        guard row >= 0, target >= 0, target < numberOfRows() else { NSSound.beep(); return }
        if mode == .post { statusItems.swapAt(row, target) } else { userItems.swapAt(row, target) }
        persist()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        tableView.scrollRowToVisible(target)
    }

    private func persist() {
        let snapshot = SpeechSettings(status: statusItems, user: userItems)
        settings.update { $0.speech = snapshot }
    }
}

extension SpeechSettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { numberOfRows() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            ])
        }
        configure(cell, at: row)
        return cell
    }

    /// Visually show a check mark, but make VoiceOver read just "<name>, checked"
    /// / "<name>, unchecked" — no "checkbox" noun.
    private func configure(_ view: NSView, at row: Int) {
        guard let cell = view as? NSTableCellView, let label = cell.textField else { return }
        let on = isEnabled(row)
        let name = fieldName(row)
        label.stringValue = "\(on ? "✓" : "  ")  \(name)"
        label.setAccessibilityLabel("\(name), \(on ? "checked" : "unchecked")")
    }
}
