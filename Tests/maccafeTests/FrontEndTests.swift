import MCP
import ServiceManagement
import Testing

@testable import maccafe

@Suite("Reading arguments an MCP client sent")
struct MCPArgumentTests {
    @Test("takes the duration and the flag a well formed call sends")
    func readsAWellFormedCall() throws {
        let arguments: [String: Value] = ["duration": .string("90m"), "system_only": .bool(true)]

        #expect(try text("duration", in: arguments) == "90m")
        #expect(try flag("system_only", in: arguments) == true)
    }

    @Test("treats a missing or null argument as omitted")
    func treatsAMissingArgumentAsOmitted() throws {
        #expect(try text("duration", in: [:]) == nil)
        #expect(try text("duration", in: [String: Value]?.none) == nil)
        #expect(try flag("system_only", in: ["system_only": .null]) == nil)
    }

    @Test("refuses a duration sent as a number instead of starting an endless hold")
    func refusesANumericDuration() {
        #expect(throws: Failure.self) { try text("duration", in: ["duration": .int(60)]) }
    }

    @Test("refuses a flag that is not a boolean")
    func refusesANonBooleanFlag() {
        #expect(throws: Failure.self) {
            try flag("system_only", in: ["system_only": .string("yes")])
        }
    }
}

@Suite("Telling a caller why the agent did not answer")
struct InstallAdviceTests {
    @Test("sends a user waiting on approval to System Settings, not back to install")
    func sendsAnUnapprovedAgentToSystemSettings() {
        let advice = Installer.advice(for: .requiresApproval)

        #expect(advice.contains("System Settings"))
        #expect(!advice.contains("maccafe install"))
    }

    @Test("asks an unregistered agent to be installed")
    func asksAnUnregisteredAgentToBeInstalled() {
        #expect(Installer.advice(for: .notRegistered).contains("maccafe install"))
    }

    @Test("says the bundle is missing when the registration outlives it")
    func reportsAMissingBundle() {
        #expect(Installer.advice(for: .notFound).contains("bundle is missing"))
    }
}
