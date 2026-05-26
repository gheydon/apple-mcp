import Foundation
import MCP

@main
struct AppleMCPMain {
    static func main() async throws {
        let server = Server(
            name: "apple-mcp",
            version: "0.1.0",
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
