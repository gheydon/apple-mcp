import Foundation
import MCP

enum JSONHelpers {
    static func string(_ args: [String: Value]?, _ key: String) -> String? {
        args?[key]?.stringValue
    }

    static func int(_ args: [String: Value]?, _ key: String) -> Int? {
        if let i = args?[key]?.intValue { return i }
        if let d = args?[key]?.doubleValue { return Int(d) }
        return nil
    }

    static func bool(_ args: [String: Value]?, _ key: String) -> Bool? {
        args?[key]?.boolValue
    }

    static func date(_ args: [String: Value]?, _ key: String) -> Date? {
        guard let raw = string(args, key) else { return nil }
        return parseDate(raw)
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return d }
        }
        return nil
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func textResult(_ text: String, isError: Bool = false) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
    }

    static func jsonResult(_ value: Any, isError: Bool = false) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let str = String(data: data, encoding: .utf8) ?? "{}"
        return textResult(str, isError: isError)
    }

    static func errorResult(_ message: String) -> CallTool.Result {
        textResult("Error: \(message)", isError: true)
    }
}
