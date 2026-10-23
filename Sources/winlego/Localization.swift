import Foundation

/// Looks a string up in Localizable.strings; the key is the English text.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
