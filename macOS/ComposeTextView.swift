//
//  ComposeTextView.swift
//  FastSM (macOS)
//
//  Text view for composing that turns Return / ⌘Return into "send" vs "newline"
//  based on the user's preference, handled in keyDown so it's reliable
//  regardless of default-button key equivalents.
//

import AppKit

final class ComposeTextView: NSTextView {
    /// Called when the key combo for "send" is pressed.
    var onSubmit: (() -> Void)?
    /// Returns whether plain Return should send (⌘Return then inserts a newline).
    var enterToSend: () -> Bool = { false }

    private enum Key {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == Key.return || event.keyCode == Key.keypadEnter else {
            super.keyDown(with: event)
            return
        }
        let commandHeld = event.modifierFlags.contains(.command)
        let shouldSend = enterToSend() ? !commandHeld : commandHeld
        if shouldSend {
            onSubmit?()
        } else if commandHeld {
            // The "newline" combo is ⌘Return in this mode — insert it explicitly,
            // since AppKit won't insert a newline for a modified Return.
            insertNewline(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
