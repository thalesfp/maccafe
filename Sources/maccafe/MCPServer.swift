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

/// An omitted argument is a default; an argument of the wrong type is a mistake,
/// and answering it with a different hold than the caller asked for is worse
/// than refusing.
func text(_ name: String, in arguments: [String: Value]?) throws -> String? {
    guard let value = arguments?[name], value != .null else { return nil }

    guard let text = value.stringValue else {
        throw Failure("\(name) must be a string")
    }

    return text
}

func flag(_ name: String, in arguments: [String: Value]?) throws -> Bool? {
    guard let value = arguments?[name], value != .null else { return nil }

    guard let flag = value.boolValue else {
        throw Failure("\(name) must be true or false")
    }

    return flag
}

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
            do {
                request = try .hold(
                    duration: text("duration", in: params.arguments),
                    systemOnly: flag("system_only", in: params.arguments) ?? false
                )
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
