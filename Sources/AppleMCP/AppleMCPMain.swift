import Foundation
import MCP

@main
struct AppleMCPMain {
    static func main() async throws {
        let argv = CommandLine.arguments
        if argv.count > 1 {
            let rest = Array(argv.dropFirst(2))
            switch argv[1] {
            case "register":
                exit(CLI.runRegister(rest))
            case "unregister":
                exit(CLI.runUnregister(rest))
            case "version", "--version", "-v":
                CLI.printVersion()
                return
            case "help", "--help", "-h":
                CLI.printHelp()
                return
            default:
                // Anything else falls through to the MCP server. MCP hosts launch
                // the binary with no arguments, which is the common path.
                break
            }
        }

        let server = Server(
            name: "apple-mcp",
            version: AppVersion.current,
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: ToolDefinitions.all())
        }

        await server.withMethodHandler(CallTool.self) { params in
            await ToolHandlers.handle(name: params.name, arguments: params.arguments)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
