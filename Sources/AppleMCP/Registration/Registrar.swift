import Foundation

// Hosts whose MCP server config we know how to update.
enum MCPHost: String, CaseIterable, Sendable {
    case claudeDesktop = "claude-desktop"
    case claudeCode = "claude-code"

    var displayName: String {
        switch self {
        case .claudeDesktop: return "Claude Desktop"
        case .claudeCode: return "Claude Code"
        }
    }

    var configPath: URL {
        // Respect $HOME so tests can sandbox via env override. FileManager's
        // homeDirectoryForCurrentUser uses getpwuid_r() and ignores $HOME.
        let home: URL
        if let env = ProcessInfo.processInfo.environment["HOME"], !env.isEmpty {
            home = URL(fileURLWithPath: env)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        switch self {
        case .claudeDesktop:
            return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .claudeCode:
            return home.appendingPathComponent(".claude.json")
        }
    }

    var configDir: URL { configPath.deletingLastPathComponent() }

    // Marker file/dir whose presence suggests the host is installed at all.
    var presenceMarker: URL { configDir }
}

struct DetectedHost: Sendable {
    let host: MCPHost
    let configExists: Bool
    let presenceLikely: Bool
    let alreadyRegistered: Bool
    let registeredCommand: String?
}

enum RegistrarError: Error, CustomStringConvertible {
    case invalidJSON(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidJSON(let s): return "Invalid JSON: \(s)"
        case .writeFailed(let s): return "Write failed: \(s)"
        }
    }
}

enum Registrar {
    static let entryName = "apple"

    static func detect() -> [DetectedHost] {
        MCPHost.allCases.map { host in
            let fm = FileManager.default
            let configExists = fm.fileExists(atPath: host.configPath.path)
            let presenceLikely = fm.fileExists(atPath: host.presenceMarker.path)

            var registered = false
            var command: String? = nil
            if configExists,
               let data = try? Data(contentsOf: host.configPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["mcpServers"] as? [String: Any],
               let apple = servers[entryName] as? [String: Any] {
                registered = true
                command = apple["command"] as? String
            }

            return DetectedHost(
                host: host,
                configExists: configExists,
                presenceLikely: presenceLikely,
                alreadyRegistered: registered,
                registeredCommand: command
            )
        }
    }

    static func register(host: MCPHost, executablePath: String) throws {
        let path = host.configPath
        let fm = FileManager.default

        // Ensure parent directory exists.
        let dir = host.configDir
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var root: [String: Any] = [:]
        if fm.fileExists(atPath: path.path) {
            let data = try Data(contentsOf: path)
            // Backup the existing file before mutating it. Never overwrite an
            // existing .bak — that would clobber the pristine pre-modification
            // state if the user re-runs this command. Use a timestamped
            // sidecar instead.
            writeBackup(of: data, for: path)
            if !data.isEmpty {
                guard let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
                    throw RegistrarError.invalidJSON("\(path.path) does not contain a JSON object at the top level")
                }
                root = parsed
            }
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers[entryName] = ["command": executablePath]
        root["mcpServers"] = servers

        do {
            let out = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try out.write(to: path, options: .atomic)
        } catch let e as RegistrarError {
            throw e
        } catch {
            throw RegistrarError.writeFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func unregister(host: MCPHost) throws -> Bool {
        let path = host.configPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: path.path) else { return false }

        let data = try Data(contentsOf: path)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var servers = root["mcpServers"] as? [String: Any],
              servers[entryName] != nil else {
            return false
        }

        writeBackup(of: data, for: path)

        servers.removeValue(forKey: entryName)
        if servers.isEmpty {
            root.removeValue(forKey: "mcpServers")
        } else {
            root["mcpServers"] = servers
        }

        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try out.write(to: path, options: .atomic)
        return true
    }

    // Write `data` to <path>.bak if that file does not exist yet, otherwise
    // to <path>.YYYYmmddHHMMSS.bak. The pristine first backup is preserved.
    private static func writeBackup(of data: Data, for path: URL) {
        let fm = FileManager.default
        let primary = path.appendingPathExtension("bak")
        if !fm.fileExists(atPath: primary.path) {
            try? data.write(to: primary, options: .atomic)
            return
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        let stamp = f.string(from: Date())
        let timestamped = path.appendingPathExtension("\(stamp).bak")
        try? data.write(to: timestamped, options: .atomic)
    }
}
