import Foundation

/// Evaluates only the keywords in the bundled, hash-pinned frozen schemas. Not a general JSON Schema engine.
struct FrozenValidator: Sendable {
    let schemas: [String: JSONValue]
    init(schemaNames: [String] = ["build", "selection", "common"]) throws {
        var schemas: [String: JSONValue] = [:]
        for name in schemaNames {
            guard let url = Bundle.module.url(forResource: name + ".schema", withExtension: "json") else { throw TransferError.unavailableSchema }
            var parser = try JSONParser(Data(contentsOf: url))
            schemas[name + ".schema.json"] = try parser.parse()
        }
        self.schemas = schemas
    }
    func validateBuild(_ value: JSONValue) throws {
        guard value.object?["schema_version"] == .string("1.0.0") else { throw TransferError.unsupportedVersion }
        try check(value, schema: schemas["build.schema.json"]!, document: "build.schema.json")
    }
    func validateCatalogItem(_ value: JSONValue) throws {
        guard value.object?["schema_version"] == .string("1.0.0") else { throw TransferError.unsupportedVersion }
        guard let schema = schemas["catalog-item.schema.json"] else { throw TransferError.unavailableSchema }
        try check(value, schema: schema, document: "catalog-item.schema.json")
    }
    func validateQualityEvaluationRun(_ value: JSONValue) throws {
        guard value.object?["schema_version"] == .string("1.0.0") else { throw TransferError.unsupportedVersion }
        guard let schema = schemas["quality-evaluation-run.schema.json"] else { throw TransferError.unavailableSchema }
        try check(value, schema: schema, document: "quality-evaluation-run.schema.json")
    }
    func validateCostEstimate(_ value: JSONValue) throws {
        guard value.object?["schema_version"] == .string("1.0.0") else { throw TransferError.unsupportedVersion }
        guard let schema = schemas["cost-estimate.schema.json"] else { throw TransferError.unavailableSchema }
        try check(value, schema: schema, document: "cost-estimate.schema.json")
    }
    func check(_ value: JSONValue, schema: JSONValue, document: String) throws {
        guard let s = schema.object else { throw TransferError.unavailableSchema }
        if let ref = s["$ref"]?.string {
            let parts = ref.split(separator: "#", omittingEmptySubsequences: false)
            let file = parts[0].isEmpty ? document : String(parts[0])
            guard var target = schemas[file] else { throw TransferError.unavailableSchema }
            if parts.count > 1 {
                for key in parts[1].split(separator: "/") {
                    guard let next = target.object?[String(key)] else { throw TransferError.unavailableSchema }
                    target = next
                }
            }
            try check(value, schema: target, document: file)
        }
        if let constant = s["const"], value != constant { throw TransferError.schemaViolation }
        if let options = s["enum"]?.array, !options.contains(value) { throw TransferError.schemaViolation }
        if let type = s["type"]?.string {
            let valid: Bool
            switch (type, value) {
            case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("number", .number): valid = true
            case ("integer", .number(let n)):
                var input = n; var rounded = Decimal(); NSDecimalRound(&rounded, &input, 0, .plain); valid = n == rounded
            default: valid = false
            }
            guard valid else { throw TransferError.schemaViolation }
        }
        if let object = value.object {
            let properties = s["properties"]?.object ?? [:]
            let patterns = s["patternProperties"]?.object ?? [:]
            for key in s["required"]?.array ?? [] {
                guard let key = key.string, object[key] != nil else { throw TransferError.schemaViolation }
            }
            for (key, item) in object {
                var matched = false
                if let child = properties[key] { matched = true; try check(item, schema: child, document: document) }
                for (pattern, child) in patterns where matches(key, pattern) {
                    matched = true; try check(item, schema: child, document: document)
                }
                if !matched && s["additionalProperties"] == .bool(false) { throw TransferError.schemaViolation }
            }
        }
        if let array = value.array {
            if let min = s["minItems"]?.number, Decimal(array.count) < min { throw TransferError.schemaViolation }
            if let child = s["items"] { for item in array { try check(item, schema: child, document: document) } }
            if s["uniqueItems"] == .bool(true) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                var seen = Set<Data>()
                for item in array {
                    guard seen.insert(try encoder.encode(item)).inserted else { throw TransferError.schemaViolation }
                }
            }
        }
        if let string = value.string {
            let count = Decimal(string.unicodeScalars.count)
            if let min = s["minLength"]?.number, count < min { throw TransferError.schemaViolation }
            if let max = s["maxLength"]?.number, count > max { throw TransferError.schemaViolation }
            if let pattern = s["pattern"]?.string, !matches(string, pattern) { throw TransferError.schemaViolation }
            if let format = s["format"]?.string {
                if format == "date-time" && !Self.timestamp(string) { throw TransferError.schemaViolation }
                if format == "uri" && !Self.uri(string) { throw TransferError.schemaViolation }
            }
        }
        if let n = value.number {
            if let min = s["minimum"]?.number, n < min { throw TransferError.schemaViolation }
            if let min = s["exclusiveMinimum"]?.number, n <= min { throw TransferError.schemaViolation }
            if let max = s["maximum"]?.number, n > max { throw TransferError.schemaViolation }
        }
        for child in s["allOf"]?.array ?? [] { try check(value, schema: child, document: document) }
        if let condition = s["if"], let then = s["then"] {
            if (try? check(value, schema: condition, document: document)) != nil { try check(value, schema: then, document: document) }
        }
    }
    private func matches(_ string: String, _ pattern: String) -> Bool {
        // Strict end-of-input avoids ICU's `$` accepting a terminal newline.
        let strict = pattern.hasSuffix("$") ? String(pattern.dropLast()) + "\\z" : pattern
        return string.range(of: strict, options: .regularExpression) != nil
    }
    static func uri(_ value: String) -> Bool {
        // Conservative RFC3986 subset, checked on raw bytes before Foundation can repair input.
        // IP-literal hosts (IPv6/IPvFuture) are intentionally unsupported by this client.
        guard let colon = value.firstIndex(of: ":"),
              String(value[..<colon]).range(of: #"\A[A-Za-z][A-Za-z0-9+.-]*\z"#, options: .regularExpression) != nil else { return false }
        let pchar = #"(?:[A-Za-z0-9._~!$&'()*+,;=:@-]|%[0-9A-Fa-f]{2})"#
        var rest = String(value[value.index(after: colon)...])
        let fragmentParts = rest.split(separator: "#", omittingEmptySubsequences: false)
        guard fragmentParts.count <= 2 else { return false }
        if fragmentParts.count == 2, String(fragmentParts[1]).range(of: "\\A(?:" + pchar + "|[/?])*\\z", options: .regularExpression) == nil { return false }
        rest = String(fragmentParts[0])
        if let question = rest.firstIndex(of: "?") {
            let query = String(rest[rest.index(after: question)...])
            guard query.range(of: "\\A(?:" + pchar + "|[/?])*\\z", options: .regularExpression) != nil else { return false }
            rest = String(rest[..<question])
        }
        if rest.hasPrefix("//") {
            rest.removeFirst(2)
            let slash = rest.firstIndex(of: "/") ?? rest.endIndex
            let authority = String(rest[..<slash])
            let authorityPattern = #"\A(?:(?:[A-Za-z0-9._~!$&'()*+,;=:-]|%[0-9A-Fa-f]{2})*@)?(?:[A-Za-z0-9._~!$&'()*+,;=-]|%[0-9A-Fa-f]{2})*(?::[0-9]*)?\z"#
            guard authority.range(of: authorityPattern, options: .regularExpression) != nil else { return false }
            rest = String(rest[slash...])
        }
        return rest.range(of: "\\A(?:" + pchar + "|/)*\\z", options: .regularExpression) != nil
    }
    static func timestamp(_ value: String) -> Bool {
        let pattern = #"\A([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?(?:[Zz]|[+-]([0-9]{2}):([0-9]{2}))\z"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return false }
        let text = value as NSString
        func n(_ i: Int) -> Int { let r = match.range(at: i); return r.location == NSNotFound ? 0 : Int(text.substring(with: r)) ?? -1 }
        let year = n(1), month = n(2), day = n(3)
        guard year > 0, (1...12).contains(month), n(4) < 24, n(5) < 60, n(6) < 60, n(7) < 24, n(8) < 60 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return (1...[31,leap ? 29 : 28,31,30,31,30,31,31,30,31,30,31][month-1]).contains(day)
    }
}
