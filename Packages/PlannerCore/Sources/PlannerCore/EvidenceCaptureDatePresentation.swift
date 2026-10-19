import Foundation

/// A date-only display derived from an already validated capture date. The
/// canonical value remains available even if Foundation cannot format it exactly.
public struct EvidenceCaptureDatePresentation: Equatable, Sendable {
    public let canonicalDate: String
    public let localizedDate: String?
}

extension EvidenceCaptureDate {
    /// Uses the locale's date order, month names and numbering, while preserving
    /// this type's proleptic Gregorian calendar. No caller time zone or current
    /// instant can shift the retained day or establish an expiry.
    public func presentation(locale: Locale) -> EvidenceCaptureDatePresentation {
        let canonical = captureDateFormatter(locale: Locale(identifier: "en_US_POSIX"))
        canonical.dateFormat = "yyyy-MM-dd"
        guard let date = canonical.date(from: rawValue),
              canonical.string(from: date) == rawValue else {
            return EvidenceCaptureDatePresentation(canonicalDate: rawValue, localizedDate: nil)
        }

        let localized = captureDateFormatter(locale: locale)
        localized.dateStyle = .long
        localized.timeStyle = .none
        let text = localized.string(from: date)
        return EvidenceCaptureDatePresentation(canonicalDate: rawValue,
            localizedDate: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text)
    }
}

private func captureDateFormatter(locale: Locale) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Proleptic Gregorian 0000-01-01, before every admitted year (0001...9999).
    // The internal UTC anchor is never returned as a captured instant.
    formatter.gregorianStartDate = Date(timeIntervalSince1970: -62_167_219_200)
    formatter.isLenient = false
    formatter.doesRelativeDateFormatting = false
    return formatter
}
