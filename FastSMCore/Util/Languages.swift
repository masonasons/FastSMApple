//
//  Languages.swift
//  FastSMCore
//
//  A small curated list of posting languages for the compose picker.
//

import Foundation

public enum Languages {
    public static let codes = [
        "en", "es", "fr", "de", "pt", "it", "nl", "ru", "ja", "ko",
        "zh", "ar", "hi", "pl", "tr", "sv", "fi", "da", "nb", "cs",
        "uk", "id", "th", "vi", "el", "he", "ro", "hu",
    ]

    /// Localized display name for a language code (falls back to the code).
    public static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// The device's language code if it's one we offer, else English.
    public static var deviceDefault: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return codes.contains(code) ? code : "en"
    }
}
