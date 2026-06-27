//
//  MediaPlayerWindowController.swift
//  FastSM (macOS)
//
//  A lightweight, VoiceOver-friendly player for a post's audio/video (Shift+
//  Return). Plain controls — Play/Pause, a scrubber, time — instead of AVKit's
//  chrome; Space toggles, Left/Right seek ±10s.
//

import AppKit
import AVFoundation

@MainActor
final class MediaPlayerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the window closes so the owner can release this controller.
    var onClose: (() -> Void)?
    private let player: AVPlayer
    private let playButton = NSButton()
    private let slider = NSSlider()
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    private var timeObserver: Any?
    private var duration: Double = 0

    init(url: URL, title: String) {
        player = AVPlayer(url: url)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        observeTime()
    }

    func windowWillClose(_ notification: Foundation.Notification) {
        player.pause()
        onClose?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
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

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 10
        playButton.title = "Pause"
        playButton.bezelStyle = .rounded
        playButton.target = self
        playButton.action = #selector(togglePlay(_:))
        playButton.setAccessibilityLabel("Play or pause")
        controls.addArrangedSubview(playButton)
        timeLabel.textColor = .secondaryLabelColor
        controls.addArrangedSubview(timeLabel)
        stack.addArrangedSubview(controls)

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.target = self
        slider.action = #selector(scrub(_:))
        slider.setAccessibilityLabel("Playback position")
        slider.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(playButton)
        player.play()
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if duration == 0, let item = player.currentItem {
                let d = item.duration.seconds
                if d.isFinite, d > 0 { duration = d; slider.maxValue = d }
            }
            let current = time.seconds
            if !slider.isHighlighted { slider.doubleValue = current }
            timeLabel.stringValue = "\(Self.format(current)) / \(Self.format(duration))"
        }
    }

    @objc private func togglePlay(_ sender: Any?) {
        if player.timeControlStatus == .playing {
            player.pause(); playButton.title = "Play"
        } else {
            player.play(); playButton.title = "Pause"
        }
    }

    @objc private func scrub(_ sender: NSSlider) {
        player.seek(to: CMTime(seconds: sender.doubleValue, preferredTimescale: 600))
    }

    private func seek(by delta: Double) {
        let target = max(0, min(duration, player.currentTime().seconds + delta))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: togglePlay(nil)                 // Space
        case 123: seek(by: -10)                  // Left
        case 124: seek(by: 10)                   // Right
        case 126: adjustVolume(by: 0.1)          // Up
        case 125: adjustVolume(by: -0.1)         // Down
        default: super.keyDown(with: event)
        }
    }

    private func adjustVolume(by delta: Float) {
        player.volume = max(0, min(1, player.volume + delta))
        let pct = Int((player.volume * 100).rounded())
        NSAccessibility.post(element: window ?? NSApp, notification: .announcementRequested,
                             userInfo: [.announcement: "Volume \(pct)%",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
