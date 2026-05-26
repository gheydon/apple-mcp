import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum AppleScriptError: Error, CustomStringConvertible {
    case compilationFailed(String)
    case executionFailed(String)

    var description: String {
        switch self {
        case .compilationFailed(let s): return "AppleScript compile error: \(s)"
        case .executionFailed(let s): return "AppleScript execution error: \(s)"
        }
    }
}

enum AppleScriptRunner {
    @discardableResult
    static func run(_ source: String) throws -> String {
        #if canImport(AppKit)
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.compilationFailed("invalid script source")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            let message = err[NSAppleScript.errorMessage] as? String ?? "unknown"
            throw AppleScriptError.executionFailed(message)
        }
        return result.stringValue ?? ""
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            throw AppleScriptError.executionFailed(String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)")
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #endif
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 2)
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default: out.append(c)
            }
        }
        return out
    }
}
