import Foundation

struct ContractBoundaryKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
func contractReject(_ decoder: Decoder, _ message: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
}
func contractKeys(_ decoder: Decoder, _ allowed: [String]) throws {
    let c = try decoder.container(keyedBy: ContractBoundaryKey.self)
    if c.allKeys.contains(where: { !allowed.contains($0.stringValue) }) {
        throw contractReject(decoder, "Unknown property in frozen-v1 object")
    }
}
func contractMatches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}
func contractID(_ value: String) -> Bool {
    contractMatches(value, "\\A[a-z][a-z0-9._:-]{2,119}\\z")
}

// Explicit Gregorian validation prevents Foundation's date-parser normalization.
// Leap-second timestamps are outside this client's supported representation.
func contractTimestamp(_ text: String) -> Bool {
    let pattern = #"\A([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?(?:[Zz]|[+-]([0-9]{2}):([0-9]{2}))\z"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return false }
    let ns = text as NSString
    func component(_ index: Int) -> Int {
        let range = match.range(at: index)
        return range.location == NSNotFound ? 0 : Int(ns.substring(with: range)) ?? -1
    }
    let year = component(1), month = component(2), day = component(3)
    guard year >= 1, (1...12).contains(month),
          (0...23).contains(component(4)), (0...59).contains(component(5)),
          (0...59).contains(component(6)), (0...23).contains(component(7)),
          (0...59).contains(component(8)) else { return false }
    let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return (1...days[month - 1]).contains(day)
}
