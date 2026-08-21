import Foundation
import MCP

private let onTool = Tool(
    name: "caffeine_on",
    description: """
        Keep this Mac awake. The hold runs in the maccafe agent, so it outlives \
        this session and lasts until caffeine_off or the duration runs out.
        """,
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "duration": .object([
                "type": .string("string"),
                "description": .string(
                    "How long to stay awake, for example \(DurationText.examples). Omit to stay awake until turned off."
                ),
            ]),
            "system_only": .object([
                "type": .string("boolean"),
                "description": .string("Let the display sleep, and only keep the system awake."),
            ]),
        ]),
    ])
)

private let offTool = Tool(
    name: "caffeine_off",
    description: "Let this Mac sleep normally again.",
    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
)

private let statusTool = Tool(
    name: "caffeine_status",
    description: "Report whether this Mac is being kept awake, and for how much longer.",
    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
)

func serveMCP() async throws {
    let server = Server(
        name: "maccafe",
        version: Maccafe.configuration.version,
        capabilities: .init(tools: .init())
    )

    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: [onTool, offTool, statusTool])
    }

    await server.withMethodHandler(CallTool.self) { params in
        let request: Request
        switch params.name {
        case "caffeine_on":
            let duration = params.arguments?["duration"]?.stringValue
            let systemOnly = params.arguments?["system_only"]?.boolValue ?? false

            do {
                request = try .hold(duration: duration, systemOnly: systemOnly)
            } catch {
                throw MCPError.invalidParams("\(error)")
            }

        case "caffeine_off":
            request = .off

        case "caffeine_status":
            request = .status

        default:
            throw MCPError.methodNotFound("no tool named \(params.name)")
        }

        do {
            let reply = try Client.send(request)

            return .init(
                content: [
                    .text(
                        text: Render.reply(reply, at: Date(), asJSON: true), annotations: nil,
                        _meta: nil)
                ], isError: false)
        } catch {
            throw MCPError.internalError("\(error)")
        }
    }

    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
}
