import Foundation

enum CLI {
    static func runRegister(_ args: [String]) -> Int32 {
        let yes = args.contains("--yes") || args.contains("-y")
        let hostFilter = extractHost(args)
        let customPath = extractValue(args, named: "--path")
        let executablePath = customPath ?? currentExecutablePath()

        var didAny = false
        var anySkipped = false

        for h in Registrar.detect() {
            if let filter = hostFilter, filter != h.host {
                continue
            }

            // If the user didn't filter and we can't see any sign of the host
            // being installed, skip silently rather than offer to create config.
            if hostFilter == nil && !h.presenceLikely {
                anySkipped = true
                stderrLine("· \(h.host.displayName): not detected, skipping")
                continue
            }

            let status: String
            if h.alreadyRegistered {
                status = "currently → \(h.registeredCommand ?? "?")"
            } else {
                status = "not registered"
            }

            stderrLine("\(h.host.displayName)  [\(status)]")
            stderrLine("  config: \(h.host.configPath.path)")

            let proceed: Bool
            if yes {
                proceed = true
            } else {
                fputs("  update? [y/N] ", stderr)
                proceed = readYesNo()
            }
            guard proceed else { continue }

            do {
                try Registrar.register(host: h.host, executablePath: executablePath)
                stderrLine("  ✓ registered (command = \(executablePath))")
                didAny = true
            } catch {
                stderrLine("  ✗ \(error)")
            }
        }

        if didAny {
            stderrLine("")
            stderrLine("Done. Restart your MCP host to pick up the change.")
        } else if !anySkipped {
            stderrLine("Nothing to update.")
        }
        return didAny ? 0 : 1
    }

    static func runUnregister(_ args: [String]) -> Int32 {
        let yes = args.contains("--yes") || args.contains("-y")
        let hostFilter = extractHost(args)
        var didAny = false

        for h in Registrar.detect() {
            if let filter = hostFilter, filter != h.host { continue }
            if !h.alreadyRegistered { continue }

            stderrLine("\(h.host.displayName)")
            stderrLine("  config: \(h.host.configPath.path)")

            let proceed: Bool
            if yes {
                proceed = true
            } else {
                fputs("  remove apple entry? [y/N] ", stderr)
                proceed = readYesNo()
            }
            guard proceed else { continue }

            do {
                if try Registrar.unregister(host: h.host) {
                    stderrLine("  ✓ unregistered")
                    didAny = true
                }
            } catch {
                stderrLine("  ✗ \(error)")
            }
        }

        if !didAny {
            stderrLine("Nothing to unregister.")
        }
        return didAny ? 0 : 1
    }

    static func printHelp() {
        let text = """
        apple-mcp — Swift MCP server for macOS Calendar, Reminders, Contacts, and Messages

        Usage:
          apple-mcp                       Run the MCP server (stdio; this is what your MCP host invokes)
          apple-mcp register [opts]       Register the binary with detected MCP hosts
          apple-mcp unregister [opts]     Remove the apple entry from MCP host configs
          apple-mcp version               Print version
          apple-mcp help                  Print this help

        Options for register / unregister:
          --host <claude-desktop|claude-code>   Target only this host
          --yes, -y                              Non-interactive; assume yes to every prompt
          --path <path>                          (register) Use a specific binary path
                                                 instead of the running executable
        """
        print(text)
    }

    static func printVersion() {
        print("apple-mcp \(AppVersion.current)")
    }

    // MARK: helpers

    private static func currentExecutablePath() -> String {
        if let p = Bundle.main.executablePath { return p }
        return CommandLine.arguments[0]
    }

    private static func extractHost(_ args: [String]) -> MCPHost? {
        guard let value = extractValue(args, named: "--host") else { return nil }
        return MCPHost(rawValue: value.lowercased())
    }

    private static func extractValue(_ args: [String], named flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func readYesNo() -> Bool {
        guard let line = readLine() else { return false }
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "y" || t == "yes"
    }

    private static func stderrLine(_ s: String) {
        fputs(s + "\n", stderr)
    }
}
