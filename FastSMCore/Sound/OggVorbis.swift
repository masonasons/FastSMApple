//
//  OggVorbis.swift
//  FastSMCore
//
//  Decodes OGG Vorbis (FastSM soundpacks are OGG) to PCM using the vendored
//  stb_vorbis decoder, then wraps it as a WAV so it can play through
//  AVAudioPlayer — Apple's audio frameworks can't decode Vorbis natively.
//

import Foundation
// Keep the vendored C decoder internal to this framework so consumers (the apps)
// don't need the CVorbis module on their search path.
@_implementationOnly import CVorbis

enum OggVorbis {
    /// Decode OGG Vorbis bytes into in-memory WAV (PCM 16-bit) data, or nil.
    static func decodeToWAV(_ data: Data) -> Data? {
        var channels: Int32 = 0
        var sampleRate: Int32 = 0
        var output: UnsafeMutablePointer<Int16>?

        let framesPerChannel: Int32 = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return stb_vorbis_decode_memory(base, Int32(data.count), &channels, &sampleRate, &output)
        }

        guard framesPerChannel > 0, channels > 0, sampleRate > 0, let output else { return nil }
        defer { free(output) }

        let sampleCount = Int(framesPerChannel) * Int(channels)
        let pcm = UnsafeBufferPointer(start: output, count: sampleCount)
        return makeWAV(pcm: pcm, channels: Int(channels), sampleRate: Int(sampleRate))
    }

    /// Wrap interleaved little-endian Int16 PCM in a canonical WAV container.
    private static func makeWAV(pcm: UnsafeBufferPointer<Int16>, channels: Int, sampleRate: Int) -> Data {
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataBytes = pcm.count * MemoryLayout<Int16>.size

        var data = Data(capacity: 44 + dataBytes)
        func appendUInt32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func appendUInt16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)                      // PCM fmt chunk size
        appendUInt16(1)                       // audio format = PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataBytes))
        // Apple platforms are little-endian, so native Int16 matches WAV PCM.
        data.append(Data(buffer: pcm))
        return data
    }
}
