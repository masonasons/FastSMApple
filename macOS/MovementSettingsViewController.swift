//
//  MovementSettingsViewController.swift
//  FastSM (macOS)
//
//  Settings → Movement: choose which timeline-movement units Option+Left/Right
//  cycles through (and Option+Up/Down jumps by). A table of checkable units;
//  toggle to include/exclude, Option+Up/Down (or the buttons) to reorder.
//

import AppKit
import FastSMCore

@MainActor
final class MovementSettingsViewController: NSViewController {
    private let settings: SettingsStore
    private let tableView = SpeechTableView()   // reused: Option+Up/Down reorder, Space toggle
    private let cellID = NSUserInterfaceItemIdentifier("MovementCell")
    private var items: [MovementItem]

    init(settings: SettingsStore) {
        self.settings = settings
        self.items = settings.settings.movement.items
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("unit"))
        column.title = "Movement units"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.setAccessibilityLabel("Movement units, in order")
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
            "Press Space (or click) to enable/disable a unit. Reorder with Option+Up / Option+Down or the buttons. In a timeline, Option+Left/Right picks a unit and Option+Up/Down jumps by it.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scroll)
        container.addSubview(buttonRow)
        container.addSubview(hint)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 480),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scroll.heightAnchor.constraint(equalToConstant: 280),

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
        if tableView.selectedRow < 0, !items.isEmpty {
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
        guard items.indices.contains(row) else { return }
        items[row].enabled.toggle()
        persist()
        if let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
            configure(rowView, at: row)
        }
        announce(items[row].enabled ? "checked" : "unchecked")
    }

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
        guard items.indices.contains(row), items.indices.contains(target) else { NSSound.beep(); return }
        items.swapAt(row, target)
        persist()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        tableView.scrollRowToVisible(target)
    }

    private func persist() {
        settings.update { $0.movement = MovementSettings(items: items) }
    }
}

extension MovementSettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

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

    private func configure(_ view: NSView, at row: Int) {
        guard let cell = view as? NSTableCellView, let label = cell.textField, items.indices.contains(row) else { return }
        let on = items[row].enabled
        let name = items[row].unit.title
        label.stringValue = "\(on ? "✓" : "  ")  \(name)"
        label.setAccessibilityLabel("\(name), \(on ? "checked" : "unchecked")")
    }
}
