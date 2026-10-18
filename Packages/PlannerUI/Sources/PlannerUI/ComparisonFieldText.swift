import Foundation
import PlannerTransfer

/// Explicit type labels keep user-authored text distinct from absent, hidden,
/// empty, boolean and null values. Text keeps its original line breaks and length.
enum ComparisonFieldText {
    static func display(_ value: ComparedFieldValue) -> String {
        switch value {
        case .absent: return "Not set (field absent)"
        case .hidden: return "Hidden for privacy"
        case .value(let value):
            switch value {
            case .string(let text): return text.isEmpty ? "Empty text" : "Text: " + text
            case .bool(let flag): return flag ? "Boolean: true" : "Boolean: false"
            case .null: return "Null value"
            case .number: return "Number: " + encoded(value)
            case .array: return "Array: " + encoded(value)
            case .object: return "Object: " + encoded(value)
            }
        }
    }

    private static func encoded(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "Value unavailable" }
        return String(decoding: data, as: UTF8.self)
    }
}
