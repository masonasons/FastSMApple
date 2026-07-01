//
//  ComposeView.swift
//  FastSM (iOS)
//
//  Compose a post/reply/quote with a live character counter, content warning,
//  visibility, posting language, an optional poll (Mastodon), and optional
//  scheduling (Mastodon).
//

import SwiftUI
import UIKit
import FastSMCore

struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var replyTo: Status?
    var quoting: Status?
    var editing: Status?

    @State private var text = ""
    @State private var spoiler = ""
    @State private var visibility: FastSMCore.Visibility = .public
    @State private var language = Languages.deviceDefault
    @State private var addPoll = false
    @State private var pollOptions: [String] = ["", ""]
    @State private var pollMultiple = false
    @State private var pollDuration = 86_400
    @State private var schedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var isPosting = false
    @State private var presentedError: PresentedError?

    private var account: (any SocialAccount)? { model.selectedAccount }
    private var maxChars: Int { account?.maxChars ?? 500 }
    private var remaining: Int { maxChars - text.count }
    private var supportsPolls: Bool { account?.features.polls == true }
    private var supportsScheduling: Bool { account?.features.scheduling == true }
    private var validPoll: Bool { pollOptions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2 }

    private var isEditing: Bool { editing != nil }

    private var canPost: Bool {
        guard !isPosting, remaining >= 0 else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if addPoll, !isEditing { return hasText && validPoll }
        return hasText
    }

    private static let durations: [(String, Int)] = [
        ("5 minutes", 300), ("30 minutes", 1800), ("1 hour", 3600),
        ("6 hours", 21_600), ("1 day", 86_400), ("3 days", 259_200), ("7 days", 604_800),
    ]

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing, let context = replyTo ?? quoting {
                    Section(quoting != nil ? "Quoting" : "Replying to") {
                        Text("\(context.account.bestName): \(context.text)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                if account?.features.contentWarning == true {
                    Section {
                        TextField("Content warning (optional)", text: $spoiler)
                            .accessibilityLabel("Content warning")
                    }
                }

                Section {
                    ComposeTextView(text: $text, autofocus: true, returnSends: model.settingsEnterToSend) {
                        if canPost { Task { await submit() } }
                    }
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Post text")
                } footer: {
                    Text("\(remaining)")
                        .foregroundStyle(remaining < 0 ? .red : .secondary)
                        .accessibilityLabel("\(remaining) characters remaining")
                }

                Section {
                    if account?.features.visibility == true, !isEditing {
                        Picker("Visibility", selection: $visibility) {
                            ForEach(FastSMCore.Visibility.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
                    Picker("Language", selection: $language) {
                        ForEach(Languages.codes, id: \.self) { Text(Languages.name($0)).tag($0) }
                    }
                }

                if supportsPolls, !isEditing {
                    Section {
                        Toggle("Add poll", isOn: $addPoll)
                        if addPoll {
                            ForEach(pollOptions.indices, id: \.self) { index in
                                TextField("Option \(index + 1)", text: $pollOptions[index])
                                    .accessibilityLabel("Poll option \(index + 1)")
                            }
                            if pollOptions.count < 4 {
                                Button("Add option") { pollOptions.append("") }
                            }
                            if pollOptions.count > 2 {
                                Button("Remove last option", role: .destructive) { pollOptions.removeLast() }
                            }
                            Toggle("Allow multiple choices", isOn: $pollMultiple)
                            Picker("Duration", selection: $pollDuration) {
                                ForEach(Self.durations, id: \.1) { Text($0.0).tag($0.1) }
                            }
                        }
                    } header: {
                        Text("Poll")
                    }
                }

                if supportsScheduling, !isEditing {
                    Section {
                        Toggle("Schedule", isOn: $schedule)
                        if schedule {
                            DatePicker("Post at", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : (schedule ? "Schedule" : "Post")) { Task { await submit() } }
                        .disabled(!canPost)
                }
            }
            .errorAlert($presentedError)
            .task {
                // Pull the exact editable source (original text + CW) for editing.
                if let editing, let source = try? await account?.postSource(editing.id) {
                    text = source.text
                    spoiler = source.spoilerText
                }
            }
            .onAppear {
                if let editing {
                    text = editing.text
                    spoiler = editing.spoilerText ?? ""
                    return
                }
                if let replyTo, let account, account.platform == .mastodon {
                    text = ReplyHelper.mentionPrefix(replyingTo: replyTo, me: account.me)
                }
                if let quoting, account?.platform == .mastodon, let url = quoting.url {
                    text += "\n\n\(url.absoluteString)"
                }
                // Match the visibility of the post being replied to.
                if let parentVisibility = replyTo?.visibility {
                    visibility = parentVisibility
                }
            }
        }
    }

    private var navTitle: String {
        if isEditing { return "Edit" }
        if quoting != nil { return "Quote" }
        return replyTo == nil ? "New Post" : "Reply"
    }

    private func submit() async {
        isPosting = true
        defer { isPosting = false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let editing {
                let draft = PostDraft(
                    text: trimmed,
                    spoilerText: account?.features.contentWarning == true ? spoiler : nil,
                    language: language
                )
                try await model.editPost(editing.id, draft: draft)
                dismiss()
                return
            }
            var poll: PollDraft?
            if addPoll {
                let options = pollOptions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                poll = PollDraft(options: options, multiple: pollMultiple, expiresInSeconds: pollDuration)
            }
            let draft = PostDraft(
                text: trimmed,
                replyToID: replyTo?.id,
                visibility: (account?.features.visibility == true) ? visibility : nil,
                spoilerText: spoiler.isEmpty ? nil : spoiler,
                quotedStatusID: account?.platform == .bluesky ? quoting?.id : nil,
                language: language,
                poll: poll,
                scheduledAt: schedule ? scheduleDate : nil
            )
            try await model.post(draft)
            dismiss()
        } catch {
            if !error.isCancellation {
                presentedError = ErrorPresenter.present(error, context: isEditing ? "Saving an edited post" : "Posting a status")
            }
        }
    }
}

/// UITextView subclass that catches the Return/Enter *key action* — which is
/// what VoiceOver Braille Screen Input's "send" gesture (three-finger swipe up)
/// and a hardware Return produce — and routes it to a closure. The two-finger
/// "new line" gesture inserts a literal "\n" instead and is left alone.
final class ComposeUITextView: UITextView {
    var onReturnKey: (() -> Void)?
    override var keyCommands: [UIKeyCommand]? {
        let command = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleReturnKey))
        command.wantsPriorityOverSystemBehavior = true
        return [command]
    }
    @objc private func handleReturnKey() { onReturnKey?() }
}

/// A UITextView-backed editor so the composer can (1) auto-focus on appear so the
/// keyboard pops up, (2) send on the Return key action (BSI's send gesture /
/// hardware Return), and (3) optionally send when the on-screen keyboard's
/// Return is tapped, if "Send with Return" is on — otherwise that inserts a
/// newline as usual.
struct ComposeTextView: UIViewRepresentable {
    @Binding var text: String
    var autofocus: Bool = false
    var returnSends: Bool = false
    var onSend: () -> Void

    func makeUIView(context: Context) -> ComposeUITextView {
        let textView = ComposeUITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = "Post text"
        textView.onReturnKey = { [weak coordinator = context.coordinator] in coordinator?.parent.onSend() }
        if autofocus {
            // Slight delay so the sheet's present animation has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if textView.window != nil { textView.becomeFirstResponder() }
            }
        }
        return textView
    }

    func updateUIView(_ uiView: ComposeUITextView, context: Context) {
        context.coordinator.parent = self   // keep returnSends / onSend current
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposeTextView
        init(_ parent: ComposeTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", parent.returnSends { parent.onSend(); return false }
            return true
        }
    }
}
