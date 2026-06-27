//
//  TimelinesViewController.swift
//  FastSM (macOS)
//
//  The left pane: a table of timelines (Home, Local, Federated, per account).
//  Up/down selects a timeline and loads its posts. Tab moves focus to the posts
//  pane.
//

import AppKit
import FastSMCore

@MainActor
final class TimelinesViewController: NSViewController {
    private let services: AppServices
    private let tableView = NavigableTableView()
    private let cellIdentifier = NSUserInterfaceItemIdentifier("TimelineCell")

    /// Called when the user presses Tab to move to the posts pane.
    var onMoveToPosts: (() -> Void)?

    /// Suppresses the selection-change handler while we set selection in code.
    private var isUpdatingSelectionProgrammatically = false

    private var refs: [TimelineRef] { services.visibleRefs }

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("timeline"))
        column.title = "Timelines"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.style = .sourceList
        tableView.setAccessibilityLabel("Timelines")
        tableView.onTab = { [weak self] in self?.onMoveToPosts?() }
        tableView.onBoundary = { [weak self] in self?.services.playEarcon(.boundary) }
        tableView.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }
        tableView.onDelete = { [weak self] in
            guard let self else { return }
            let row = self.tableView.selectedRow
            guard let full = self.fullIndex(row) else { return }
            self.services.closeTimeline(at: full)
            self.focusTable()
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    func reload() {
        tableView.reloadData()
        updateSelectionHighlight()
    }

    /// Reflect the services' selection in the table without triggering a load.
    func updateSelectionHighlight() {
        guard let selected = services.selectedRef, let row = refs.firstIndex(of: selected) else { return }
        isUpdatingSelectionProgrammatically = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isUpdatingSelectionProgrammatically = false
    }

    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    /// Map a visible (current-account) row to the full timelineRefs index.
    private func fullIndex(_ visibleRow: Int) -> Int? {
        guard refs.indices.contains(visibleRow) else { return nil }
        return services.timelineRefs.firstIndex(of: refs[visibleRow])
    }

    // MARK: Right-click menu

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard let full = fullIndex(row) else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = full
        }
        add("Clear Items", #selector(clearRow(_:)))
        add(services.isMuted(at: full) ? "Unmute" : "Mute", #selector(muteRow(_:)))
        if refs[row].source.isDismissable {
            add("Close", #selector(closeRow(_:)))
        }
        return menu
    }

    @objc private func clearRow(_ sender: NSMenuItem) { services.clearTimeline(at: sender.tag) }
    @objc private func muteRow(_ sender: NSMenuItem) { services.toggleMute(at: sender.tag) }
    @objc private func closeRow(_ sender: NSMenuItem) {
        services.closeTimeline(at: sender.tag)
        focusTable()
    }
}

extension TimelinesViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { refs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        // Defensive: NSTableView can request a stale row during async layout.
        guard refs.indices.contains(row) else { return cell }
        let title = services.displayTitle(for: refs[row])
        cell.textField?.stringValue = title
        cell.setAccessibilityLabel(title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Foundation.Notification) {
        guard !isUpdatingSelectionProgrammatically else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        services.playEarcon(.navigate)
        services.selectVisible(at: row)
    }
}
