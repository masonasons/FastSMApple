//
//  ComposeWindowController.swift
//  FastSM (macOS)
//
//  A sheet for composing a post/reply/quote: text + live counter, content
//  warning, visibility, posting language, an optional poll (Mastodon), and
//  optional scheduling (Mastodon).
//

import AppKit
import FastSMCore

@MainActor
final class ComposeWindowController: NSWindowController, NSTextViewDelegate {
    private let services: AppServices
    private let account: any SocialAccount
    private let replyTo: Status?
    private let quoting: Status?
    private let editing: Status?
    private var isEditing: Bool { editing != nil }

    private let textView = ComposeTextView()
    private let counterLabel = NSTextField(labelWithString: "")
    private let cwField = NSTextField()
    private let visibilityPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let postButton = NSButton()

    // Poll
    private let pollCheckbox = NSButton(checkboxWithTitle: "Add poll", target: nil, action: nil)
    private let pollOptionsStack = NSStackView()
    private var pollOptionFields: [NSTextField] = []
    private let pollMultipleCheckbox = NSButton(checkboxWithTitle: "Allow multiple choices", target: nil, action: nil)
    private let pollDurationPopup = NSPopUpButton()
    private let pollContainer = NSStackView()

    // Schedule
    private let scheduleCheckbox = NSButton(checkboxWithTitle: "Schedule", target: nil, action: nil)
    private let scheduleDatePicker = NSDatePicker()

    private static let durations: [(String, Int)] = [
        ("5 minutes", 300), ("30 minutes", 1800), ("1 hour", 3600),
        ("6 hours", 21_600), ("1 day", 86_400), ("3 days", 259_200), ("7 days", 604_800),
    ]

    init(services: AppServices, account: any SocialAccount, replyTo: Status?, quoting: Status? = nil, editing: Status? = nil) {
        self.services = services
        self.account = account
        self.replyTo = replyTo
        self.quoting = quoting
        self.editing = editing

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = editing != nil ? "Edit Post" : (quoting != nil ? "Quote Post" : (replyTo == nil ? "New Post" : "Reply"))
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, onDismiss: @escaping () -> Void) {
        parent.beginSheet(window!) { _ in onDismiss() }
        window?.makeFirstResponder(textView)
        // Replace the prefilled (rendered) text with the exact editable source.
        if let editing {
            Task {
                if let source = try? await account.postSource(editing.id) {
                    textView.string = source.text
                    cwField.stringValue = source.spoilerText
                    updateCounter()
                }
            }
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        // Add to the stack first, THEN constrain — activating a cross-view
        // constraint before the view shares an ancestor throws (and AppKit
        // silently swallows it, so the sheet never appears).
        func fullWidth(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }

        // Reply / quote context.
        if !isEditing, let context = replyTo ?? quoting {
            let label = NSTextField(wrappingLabelWithString:
                "\(quoting != nil ? "Quoting" : "Replying to") \(context.account.bestName): \(context.text)")
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11)
            label.maximumNumberOfLines = 3
            fullWidth(label)
        }

        // Content warning.
        if account.features.contentWarning {
            cwField.placeholderString = "Content warning (optional)"
            cwField.setAccessibilityLabel("Content warning")
            fullWidth(cwField)
        }

        // Text editor.
        let textScroll = NSScrollView()
        textScroll.borderType = .bezelBorder
        textScroll.hasVerticalScroller = true
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.setAccessibilityLabel("Post text")
        textView.enterToSend = { [weak self] in self?.services.settings.settings.enterToSend ?? false }
        textView.onSubmit = { [weak self] in self?.post(nil) }
        textView.autoresizingMask = [.width]
        textScroll.documentView = textView
        stack.addArrangedSubview(textScroll)
        NSLayoutConstraint.activate([
            textScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            textScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        // Visibility + language.
        let optionsRow = NSStackView()
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 8
        if account.features.visibility, !isEditing {
            for visibility in Visibility.allCases {
                visibilityPopup.addItem(withTitle: visibility.displayName)
                visibilityPopup.lastItem?.representedObject = visibility.rawValue
            }
            // Default a reply's visibility to match the post being replied to.
            if let parent = replyTo?.visibility,
               let index = Visibility.allCases.firstIndex(of: parent) {
                visibilityPopup.selectItem(at: index)
            }
            visibilityPopup.setAccessibilityLabel("Visibility")
            optionsRow.addArrangedSubview(NSTextField(labelWithString: "Visibility:"))
            optionsRow.addArrangedSubview(visibilityPopup)
        }
        for code in Languages.codes {
            languagePopup.addItem(withTitle: Languages.name(code))
            languagePopup.lastItem?.representedObject = code
        }
        selectLanguage(Languages.deviceDefault)
        languagePopup.setAccessibilityLabel("Language")
        optionsRow.addArrangedSubview(NSTextField(labelWithString: "Language:"))
        optionsRow.addArrangedSubview(languagePopup)
        stack.addArrangedSubview(optionsRow)

        // Poll (Mastodon).
        if account.features.polls, !isEditing {
            pollCheckbox.target = self
            pollCheckbox.action = #selector(togglePoll(_:))
            stack.addArrangedSubview(pollCheckbox)

            pollContainer.orientation = .vertical
            pollContainer.alignment = .leading
            pollContainer.spacing = 6
            pollOptionsStack.orientation = .vertical
            pollOptionsStack.alignment = .leading
            pollOptionsStack.spacing = 6
            addPollOptionField()
            addPollOptionField()
            pollContainer.addArrangedSubview(pollOptionsStack)

            let pollButtons = NSStackView()
            pollButtons.orientation = .horizontal
            pollButtons.spacing = 8
            let addOption = NSButton(title: "Add option", target: self, action: #selector(addPollOption(_:)))
            let removeOption = NSButton(title: "Remove option", target: self, action: #selector(removePollOption(_:)))
            pollButtons.addArrangedSubview(addOption)
            pollButtons.addArrangedSubview(removeOption)
            pollContainer.addArrangedSubview(pollButtons)

            pollContainer.addArrangedSubview(pollMultipleCheckbox)

            let durationRow = NSStackView()
            durationRow.orientation = .horizontal
            durationRow.spacing = 8
            for (label, seconds) in Self.durations {
                pollDurationPopup.addItem(withTitle: label)
                pollDurationPopup.lastItem?.representedObject = seconds
            }
            pollDurationPopup.selectItem(withTitle: "1 day")
            pollDurationPopup.setAccessibilityLabel("Poll duration")
            durationRow.addArrangedSubview(NSTextField(labelWithString: "Duration:"))
            durationRow.addArrangedSubview(pollDurationPopup)
            pollContainer.addArrangedSubview(durationRow)

            pollContainer.isHidden = true
            stack.addArrangedSubview(pollContainer)
        }

        // Schedule (Mastodon).
        if account.features.scheduling, !isEditing {
            scheduleCheckbox.target = self
            scheduleCheckbox.action = #selector(toggleSchedule(_:))
            let scheduleRow = NSStackView()
            scheduleRow.orientation = .horizontal
            scheduleRow.spacing = 8
            scheduleDatePicker.datePickerElements = [.yearMonthDay, .hourMinute]
            scheduleDatePicker.dateValue = Date().addingTimeInterval(3600)
            scheduleDatePicker.minDate = Date()
            scheduleDatePicker.isHidden = true
            scheduleDatePicker.setAccessibilityLabel("Scheduled time")
            scheduleRow.addArrangedSubview(scheduleCheckbox)
            scheduleRow.addArrangedSubview(scheduleDatePicker)
            stack.addArrangedSubview(scheduleRow)
        }

        // Bottom row.
        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        counterLabel.textColor = .secondaryLabelColor
        bottom.addArrangedSubview(counterLabel)
        let hint = NSTextField(labelWithString: sendHint)
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        bottom.addArrangedSubview(hint)
        bottom.addArrangedSubview(NSView())
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        bottom.addArrangedSubview(cancelButton)
        postButton.title = isEditing ? "Save" : "Post"
        postButton.target = self
        postButton.action = #selector(post(_:))
        postButton.toolTip = sendHint
        postButton.bezelStyle = .rounded
        bottom.addArrangedSubview(postButton)
        fullWidth(bottom)

        // Prefill.
        if let editing {
            textView.string = editing.text
            cwField.stringValue = editing.spoilerText ?? ""
        } else {
            if let replyTo, account.platform == .mastodon {
                textView.string = ReplyHelper.mentionPrefix(replyingTo: replyTo, me: account.me)
            }
            if let quoting, account.platform == .mastodon, let url = quoting.url {
                textView.string += "\n\n\(url.absoluteString)"
            }
        }
        updateCounter()
    }

    private func selectLanguage(_ code: String) {
        if let index = Languages.codes.firstIndex(of: code) { languagePopup.selectItem(at: index) }
    }

    private func addPollOptionField() {
        guard pollOptionFields.count < 4 else { return }
        let field = NSTextField()
        field.placeholderString = "Option \(pollOptionFields.count + 1)"
        field.setAccessibilityLabel("Poll option \(pollOptionFields.count + 1)")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        pollOptionFields.append(field)
        pollOptionsStack.addArrangedSubview(field)
    }

    @objc private func addPollOption(_ sender: Any?) { addPollOptionField() }

    @objc private func removePollOption(_ sender: Any?) {
        guard pollOptionFields.count > 2, let last = pollOptionFields.popLast() else { return }
        pollOptionsStack.removeArrangedSubview(last)
        last.removeFromSuperview()
    }

    @objc private func togglePoll(_ sender: NSButton) {
        pollContainer.isHidden = sender.state != .on
        updateCounter()
    }

    @objc private func toggleSchedule(_ sender: NSButton) {
        scheduleDatePicker.isHidden = sender.state != .on
        postButton.title = sender.state == .on ? "Schedule" : "Post"
    }

    private var sendHint: String {
        services.settings.settings.enterToSend ? "Return to send · ⌘Return for newline" : "⌘Return to send"
    }

    private var pollIsValid: Bool {
        pollCheckbox.state != .on ||
        pollOptionFields.filter { !$0.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    private func updateCounter() {
        let remaining = account.maxChars - textView.string.count
        counterLabel.stringValue = "\(remaining)"
        counterLabel.textColor = remaining < 0 ? .systemRed : .secondaryLabelColor
        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        postButton.isEnabled = remaining >= 0 && hasText && pollIsValid
    }

    func textDidChange(_ notification: Foundation.Notification) { updateCounter() }

    @objc private func cancel(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!)
    }

    @objc private func post(_ sender: Any?) {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, textView.string.count <= account.maxChars, pollIsValid else { return }

        let language = languagePopup.selectedItem?.representedObject as? String

        // Edit mode: update the existing post (text + CW + language only).
        if let editing {
            let spoiler = account.features.contentWarning ? cwField.stringValue : nil
            let draft = PostDraft(text: text, spoilerText: spoiler, language: language)
            postButton.isEnabled = false
            Task {
                do {
                    _ = try await services.selectedController?.editPost(editing.id, draft: draft)
                    services.playEarcon(.postSent)
                    window?.sheetParent?.endSheet(window!)
                } catch {
                    postButton.isEnabled = true
                    ErrorAlert.present(error, context: "Saving an edited post",
                                       sound: services.sound, in: window)
                }
            }
            return
        }

        var visibility: Visibility?
        if account.features.visibility, let raw = visibilityPopup.selectedItem?.representedObject as? String {
            visibility = Visibility(rawValue: raw)
        }
        let spoiler = account.features.contentWarning ? cwField.stringValue : nil

        var poll: PollDraft?
        if account.features.polls, pollCheckbox.state == .on {
            let options = pollOptionFields.map { $0.stringValue.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let seconds = (pollDurationPopup.selectedItem?.representedObject as? Int) ?? 86_400
            poll = PollDraft(options: options, multiple: pollMultipleCheckbox.state == .on, expiresInSeconds: seconds)
        }
        let scheduledAt = (account.features.scheduling && scheduleCheckbox.state == .on) ? scheduleDatePicker.dateValue : nil

        let draft = PostDraft(
            text: text,
            replyToID: replyTo?.id,
            visibility: visibility,
            spoilerText: (spoiler?.isEmpty == false) ? spoiler : nil,
            quotedStatusID: account.platform == .bluesky ? quoting?.id : nil,
            language: language,
            poll: poll,
            scheduledAt: scheduledAt
        )

        postButton.isEnabled = false
        Task {
            do {
                _ = try await services.selectedController?.post(draft)
                services.playEarcon(.postSent)
                window?.sheetParent?.endSheet(window!)
            } catch {
                postButton.isEnabled = true
                ErrorAlert.present(error, context: "Posting a status",
                                   sound: services.sound, in: window)
            }
        }
    }
}
