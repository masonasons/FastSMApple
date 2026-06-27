//
//  Demojify.swift
//  FastSMCore
//
//  Optional emoji removal for displayed text (OG FastSM "demojify").
//

import Foundation

public extension String {
    /// Returns the string with emoji removed and any doubled spaces collapsed.
    func demojified() -> String {
        guard unicodeScalars.contains(where: { $0.properties.isEmoji }) else { return self }
        var result = ""
        result.reserveCapacity(count)
        for scalar in unicodeScalars {
            // Drop emoji and the variation/zero-width joiners that compose them,
            // but keep plain ASCII digits/# that merely *can* form keycaps.
            let isEmoji = scalar.properties.isEmoji && (scalar.properties.isEmojiPresentation || scalar.value > 0x2000)
            let isJoiner = scalar.value == 0x200D || scalar.value == 0xFE0F
            if isEmoji || isJoiner { continue }
            result.unicodeScalars.append(scalar)
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Conditionally demojify.
    func demojified(if condition: Bool) -> String {
        condition ? demojified() : self
    }
}
