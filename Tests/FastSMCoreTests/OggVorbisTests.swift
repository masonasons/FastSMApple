//
//  OggVorbisTests.swift
//  FastSMCoreTests
//
//  Verifies the vendored stb_vorbis path decodes a real bundled OGG soundpack
//  file into valid WAV data.
//

import XCTest
@testable import FastSMCore

final class OggVorbisTests: XCTestCase {
    func testDecodesBundledOggToWAV() throws {
        let bundle = Bundle(for: SoundManager.self)
        guard let url = bundle.url(forResource: "boundary", withExtension: "ogg") else {
            throw XCTSkip("Default soundpack not bundled in test environment")
        }
        let ogg = try Data(contentsOf: url)
        let wav = try XCTUnwrap(OggVorbis.decodeToWAV(ogg), "OGG should decode to WAV")
        XCTAssertGreaterThan(wav.count, 44, "WAV should have header plus samples")
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }
}
