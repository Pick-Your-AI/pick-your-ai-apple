import Foundation

/// Raw-wire errors contain neither object keys nor input values.
public enum ContractJSONError: Error, Equatable, Sendable {
    case invalidUTF8, malformed, duplicateKey, tooDeep, tooComplex
}

/// Checks framing, key uniqueness and traversal limits before Foundation builds
/// keyed containers. Existing DTOs remain the authority for syntax and values;
/// this scanner does not normalize numbers, money or the original input bytes.
struct ContractJSONPreflight {
    static let maximumDepth = 48
    static let maximumValues = 131_072

    private let bytes: [UInt8]
    private var index = 0
    private var values = 0

    /// Pricebook historically accepts Foundation's UTF-8/16/32 input forms.
    /// Called only after the original byte cap; this view never replaces the
    /// original data passed to the typed decoder or rounds numeric tokens.
    static func textView(_ data: Data) throws -> String {
        let prefix = Array(data.prefix(4))
        var encoding = String.Encoding.utf8
        var bomLength = 0
        if prefix.starts(with: [0, 0, 0xfe, 0xff]) {
            encoding = .utf32BigEndian; bomLength = 4
        } else if prefix.starts(with: [0xff, 0xfe, 0, 0]) {
            encoding = .utf32LittleEndian; bomLength = 4
        } else if prefix.starts(with: [0xfe, 0xff]) {
            encoding = .utf16BigEndian; bomLength = 2
        } else if prefix.starts(with: [0xff, 0xfe]) {
            encoding = .utf16LittleEndian; bomLength = 2
        } else if prefix.count == 4 {
            // Without a BOM, ASCII JSON punctuation identifies the byte order.
            if prefix[0] == 0 && prefix[1] == 0 && prefix[2] == 0 { encoding = .utf32BigEndian }
            else if prefix[1] == 0 && prefix[2] == 0 && prefix[3] == 0 { encoding = .utf32LittleEndian }
            else if prefix[0] == 0 && prefix[2] == 0 { encoding = .utf16BigEndian }
            else if prefix[1] == 0 && prefix[3] == 0 { encoding = .utf16LittleEndian }
        }
        guard let text = String(data: data.dropFirst(bomLength), encoding: encoding) else {
            throw encoding == .utf8 ? ContractJSONError.invalidUTF8 : ContractJSONError.malformed
        }
        return text
    }

    static func validate(_ text: String) throws {
        var scanner = Self(bytes: Array(text.utf8))
        // Foundation accepts one leading UTF-8 BOM. It is transport framing,
        // not a primitive value or whitespace allowed elsewhere in the text.
        if scanner.bytes.starts(with: [0xef, 0xbb, 0xbf]) { scanner.index = 3 }
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.index == scanner.bytes.count else { throw ContractJSONError.malformed }
    }

    private mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func string() throws -> Range<Int> {
        whitespace()
        let start = index
        guard consume(34) else { throw ContractJSONError.malformed }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 92 {
                guard index < bytes.count else { throw ContractJSONError.malformed }
                index += 1
            } else if byte == 34 {
                return start..<index
            }
        }
        throw ContractJSONError.malformed
    }

    private mutating func value(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw ContractJSONError.tooDeep }
        values += 1
        guard values <= Self.maximumValues else { throw ContractJSONError.tooComplex }
        whitespace()
        guard index < bytes.count else { throw ContractJSONError.malformed }

        if bytes[index] == 34 {
            _ = try string()
            return
        }
        if consume(123) {
            // Match Swift's eventual keyed-container semantics, including escaped
            // spellings and Unicode-equivalent keys that would otherwise collapse.
            var keys: Set<String> = []
            if consume(125) { return }
            repeat {
                let range = try string()
                guard let key = try? JSONDecoder().decode(String.self, from: Data(bytes[range]))
                else { throw ContractJSONError.malformed }
                guard keys.insert(key).inserted else { throw ContractJSONError.duplicateKey }
                guard consume(58) else { throw ContractJSONError.malformed }
                try value(depth: depth + 1)
                if consume(125) { return }
            } while consume(44)
            throw ContractJSONError.malformed
        }
        if consume(91) {
            if consume(93) { return }
            repeat {
                try value(depth: depth + 1)
                if consume(93) { return }
            } while consume(44)
            throw ContractJSONError.malformed
        }

        // Leave literal and numeric interpretation to the unchanged typed decoder.
        let start = index
        while index < bytes.count && ![9, 10, 13, 32, 34, 44, 58, 91, 93, 123, 125].contains(bytes[index]) {
            index += 1
        }
        guard index > start else { throw ContractJSONError.malformed }
    }
}
