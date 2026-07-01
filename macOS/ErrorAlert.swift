//
//  ErrorAlert.swift
//  FastSM (macOS)
//
//  One place to present an error: the specific summary as the heading, the full
//  detail in a selectable / scrollable text view (readable by VoiceOver and
//  copyable by hand), and a "Copy Details" button — instead of a generic
//  "Something went wrong" box that only plays a sound.
//

import AppKit
import FastSMCore

enum ErrorAlert {
    /// Present `error` as a sheet on `window` (app-modal if `window` is nil).
    /// Plays the error earcon (falling back to a system beep when no sound service
    /// is available) and offers "Copy Details".
    static func present(_ error: Error,
                        context: String? = nil,
                        sound: SoundManager? = nil,
                        in window: NSWindow?,
                        completion: (() -> Void)? = nil) {
        // A cancelled request isn't a failure — never show it.
        guard !error.isCancellation else { completion?(); return }
        let presented = ErrorPresenter.present(error, context: context)
        if let sound { sound.play(.error) } else { NSSound.beep() }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = presented.summary
        // The detail lives in the selectable accessory view rather than
        // informativeText so it can be read by VoiceOver and copied by hand.
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Details")
        alert.accessoryView = detailView(presented.detail)

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertSecondButtonReturn { copy(presented.detail) }
            completion?()
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    /// A read-only, selectable, scrolling text view holding the full details.
    private static func detailView(_ text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 150))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        textView.setAccessibilityLabel("Error details")
        scroll.documentView = textView
        return scroll
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
