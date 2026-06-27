//
//  TimelineCache.swift
//  FastSMCore
//
//  On-disk cache of the home timeline per account, for instant startup. Port of
//  the intent behind FastSM's TimelineCache (cache/), tuned for low memory and
//  CPU:
//
//   • An `actor`, so all encode/decode and file I/O happen off the main thread.
//   • Entries are capped (default 200) — bounds disk size, decode time, and the
//     amount of data read back into memory.
//   • Writes are debounced and coalesced, so rapid refresh/scroll bursts produce
//     at most one write per interval instead of thrashing the disk.
//   • Compact (non-pretty) JSON to keep encode cost and file size down.
//

import Foundation

public actor TimelineCache {
    private let directory: URL
    private var maxEntries: Int
    private let debounceNanoseconds: UInt64

    // Compact JSON (UTF-8) + zlib compression. JSON keeps text tight (binary
    // plist stores strings as UTF-16, which bloats emoji/Unicode-heavy posts),
    // and zlib then shrinks the highly-repetitive timeline JSON ~5-10x — the
    // best balance of small files and fast decode as cache limits grow.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private func compress(_ data: Data) -> Data? {
        try? (data as NSData).compressed(using: .zlib) as Data
    }

    private func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .zlib) as Data
    }

    /// Pending writes keyed by timeline; only the latest snapshot per key is
    /// kept, so a burst of saves collapses to one flush.
    private var pending: [String: [TimelineItem]] = [:]
    private var flushTask: Task<Void, Never>?

    public init(
        maxEntries: Int = 200,
        debounceSeconds: Double = 1.0,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.maxEntries = maxEntries
        self.debounceNanoseconds = UInt64(debounceSeconds * 1_000_000_000)
        if let directory {
            self.directory = directory
        } else {
            let base = (try? fileManager.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? fileManager.temporaryDirectory
            self.directory = base.appendingPathComponent("FastSM/timelines", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".jsonz")
    }

    /// Load cached items for a timeline key. Returns [] on miss or error.
    public func load(key: String) -> [TimelineItem] {
        guard let raw = try? Data(contentsOf: fileURL(for: key)),
              let data = decompress(raw) else { return [] }
        return (try? decoder.decode([TimelineItem].self, from: data)) ?? []
    }

    /// Schedule a (capped, debounced) save. Returns immediately.
    public func save(_ items: [TimelineItem], key: String) {
        pending[key] = Array(items.prefix(maxEntries))
        guard flushTask == nil else { return }
        flushTask = Task { [debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            await self.flush()
        }
    }

    /// Update the per-timeline item cap (from settings). Applies to future saves.
    public func setMaxEntries(_ count: Int) {
        maxEntries = max(1, count)
    }

    /// Delete a single timeline's cache (e.g. when the timeline is closed).
    public func remove(key: String) {
        pending[key] = nil
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Delete every cache file except those whose keys are in `keep` — used at
    /// launch to purge orphaned caches (closed/spawned timelines, removed
    /// accounts).
    public func removeAll(except keep: Set<String>) {
        let keepNames = Set(keep.map { fileURL(for: $0).lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        // Clean current (.jsonz) caches not in the keep set, plus any leftover
        // caches from previous formats (.json, .plist).
        let cacheExtensions: Set<String> = ["jsonz", "plist", "json"]
        for file in files where cacheExtensions.contains(file.pathExtension) && !keepNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Force any pending writes to disk now (e.g. on app termination).
    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    private func flush() {
        let snapshot = pending
        pending.removeAll(keepingCapacity: true)
        flushTask = nil
        for (key, items) in snapshot {
            guard let json = try? encoder.encode(items), let data = compress(json) else { continue }
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }
}
