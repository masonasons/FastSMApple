//
//  ImageViewerWindowController.swift
//  FastSM (macOS)
//
//  A simple, VoiceOver-friendly image viewer for a post's images. Supports more
//  than one image with Previous/Next; the alt text is shown and exposed to
//  VoiceOver.
//

import AppKit
import FastSMCore

@MainActor
final class ImageViewerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let media: [MediaAttachment]
    private var index: Int

    private let imageView = NSImageView()
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let counterLabel = NSTextField(labelWithString: "")
    private var loadToken = 0

    init(media: [MediaAttachment], startIndex: Int = 0) {
        self.media = media
        self.index = media.indices.contains(startIndex) ? startIndex : 0
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        showCurrent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Foundation.Notification) { onClose?() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setAccessibilityRole(.image)

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.isSelectable = true

        previousButton.title = "Previous"
        previousButton.bezelStyle = .rounded
        previousButton.target = self
        previousButton.action = #selector(showPrevious(_:))
        previousButton.keyEquivalent = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        nextButton.title = "Next"
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(showNext(_:))
        nextButton.keyEquivalent = String(UnicodeScalar(NSRightArrowFunctionKey)!)

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow(_:)))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"

        let controls = NSStackView(views: [previousButton, counterLabel, nextButton, NSView(), close])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(imageView)
        content.addSubview(descriptionLabel)
        content.addSubview(controls)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            descriptionLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            descriptionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            controls.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func showCurrent() {
        guard media.indices.contains(index), let url = media[index].url else { return }
        let alt = media[index].description?.isEmpty == false ? media[index].description! : "Image with no description"
        window?.title = media.count > 1 ? "Image \(index + 1) of \(media.count)" : "Image"
        counterLabel.stringValue = media.count > 1 ? "\(index + 1) / \(media.count)" : ""
        descriptionLabel.stringValue = alt
        imageView.setAccessibilityLabel(alt)
        previousButton.isEnabled = index > 0
        nextButton.isEnabled = index < media.count - 1
        previousButton.isHidden = media.count <= 1
        nextButton.isHidden = media.count <= 1
        counterLabel.isHidden = media.count <= 1

        loadToken += 1
        let token = loadToken
        imageView.image = nil
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            guard let self, token == self.loadToken else { return }
            self.imageView.image = image
        }
    }

    @objc private func showPrevious(_ sender: Any?) {
        guard index > 0 else { return }
        index -= 1
        showCurrent()
    }

    @objc private func showNext(_ sender: Any?) {
        guard index < media.count - 1 else { return }
        index += 1
        showCurrent()
    }

    @objc private func closeWindow(_ sender: Any?) { window?.close() }
}
