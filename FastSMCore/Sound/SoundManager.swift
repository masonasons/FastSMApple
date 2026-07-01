//
//  SoundManager.swift
//  FastSMCore
//
//  Earcon playback. FastSM is heavily earcon-driven. A default soundpack ships
//  inside the framework; users can override individual sounds by dropping files
//  (named with FastSM's conventions, e.g. boundary.ogg, like.ogg) into a custom
//  soundpack folder. OGG Vorbis is decoded via OggVorbis (stb_vorbis).
//

import Foundation
import AVFoundation

/// UI events that can produce an earcon. The `soundName` maps each to the file
/// base name used by FastSM soundpacks, so a real FastSM pack works as-is.
public enum Earcon: String, Sendable, CaseIterable {
    case navigate
    case boundary       // hit the top/bottom of a list
    case postSent
    case boost
    case favorite
    case unfavorite
    case bookmark
    case unbookmark
    case close          // closing/dismissing a timeline
    case delete         // clearing/deleting content
    case refresh
    case error

    /// FastSM soundpack file base name, or nil for events with no default sound.
    /// Names match FastSM's own usage so a native soundpack maps 1:1.
    public var soundName: String? {
        switch self {
        case .navigate: return nil          // per-item navigation is silent in FastSM
        case .boundary: return "boundary"   // top/bottom of a list
        case .postSent: return "send_post"
        case .boost: return "send_repost"
        case .favorite: return "like"
        case .unfavorite: return "unlike"
        case .bookmark: return "bookmark"       // silent if a soundpack lacks it
        case .unbookmark: return "unbookmark"
        case .close: return "close"
        case .delete: return "delete"
        case .refresh: return "ready"       // FastSM plays "ready" when a timeline loads
        case .error: return "error"
        }
    }
}

public protocol SoundPlaying: AnyObject, Sendable {
    func play(_ earcon: Earcon)
}

public final class SilentSoundManager: SoundPlaying, @unchecked Sendable {
    public init() {}
    public func play(_ earcon: Earcon) {}
}

@MainActor
public final class SoundManager: SoundPlaying, @unchecked Sendable {
    public var enabled: Bool = true

    /// The selected soundpack folder; nil means use the bundled Default pack.
    /// Files found here override the bundled default per-file.
    private var packDirectory: URL?
    /// Bundle holding the default soundpack (the framework bundle).
    private let bundle: Bundle
    private let fileExtensions = ["ogg", "wav", "mp3", "aiff"]
    private var players: [Earcon: AVAudioPlayer] = [:]

    private var namedPlayers: [String: AVAudioPlayer] = [:]

    public init(bundle: Bundle = Bundle(for: SoundManager.self)) {
        self.bundle = bundle
        #if os(iOS)
        // Without an active audio session AVAudioPlayer is silent on iOS.
        // .playback so earcons are heard even with the silent switch on;
        // .mixWithOthers so we don't stop music or fight VoiceOver speech.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    /// Switch the active soundpack folder (nil = built-in Default). Clears the
    /// decoded-player cache so the new pack's sounds load.
    public func setSoundpack(directory: URL?) {
        guard directory != packDirectory else { return }
        packDirectory = directory
        players.removeAll()
        namedPlayers.removeAll()
    }

    nonisolated public func play(_ earcon: Earcon) {
        Task { @MainActor in self.playOnMain(earcon) }
    }

    /// Play an arbitrary soundpack file by base name (e.g. "ready", "home").
    nonisolated public func play(named name: String) {
        Task { @MainActor in self.playOnMain(named: name) }
    }

    private func playOnMain(_ earcon: Earcon) {
        guard enabled, let player = player(for: earcon) else { return }
        player.currentTime = 0
        player.play()
    }

    private func playOnMain(named name: String) {
        guard enabled else { return }
        let player: AVAudioPlayer?
        if let cached = namedPlayers[name] {
            player = cached
        } else if let url = fileURL(forName: name), let made = makePlayer(for: url) {
            made.prepareToPlay()
            namedPlayers[name] = made
            player = made
        } else {
            player = nil
        }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for earcon: Earcon) -> AVAudioPlayer? {
        if let cached = players[earcon] { return cached }
        guard let url = fileURL(for: earcon), let player = makePlayer(for: url) else { return nil }
        player.prepareToPlay()
        players[earcon] = player
        return player
    }

    /// Locate the sound file: selected soundpack first, then the bundled default.
    private func fileURL(for earcon: Earcon) -> URL? {
        guard let base = earcon.soundName else { return nil }
        return fileURL(forName: base)
    }

    private func fileURL(forName base: String) -> URL? {
        if let dir = packDirectory {
            for ext in fileExtensions {
                let candidate = dir.appendingPathComponent("\(base).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        for ext in fileExtensions {
            if let url = bundle.url(forResource: base, withExtension: ext) { return url }
        }
        return nil
    }

    private func makePlayer(for url: URL) -> AVAudioPlayer? {
        if url.pathExtension.lowercased() == "ogg" {
            guard let data = try? Data(contentsOf: url),
                  let wav = OggVorbis.decodeToWAV(data) else { return nil }
            return try? AVAudioPlayer(data: wav)
        }
        return try? AVAudioPlayer(contentsOf: url)
    }
}
