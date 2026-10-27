import XCTest
@testable import ParviKit

@MainActor
private final class TestRuntime: ChatRuntime {
    let cookie = "test"
    let localDeviceName = "Test node"
    let connectionDescription = "Local test"
    let connectionHelp = "Local test"
    let canConnect = true
    var requests: [[String: String]] = []
    var snapshot: ((Data) -> Void)?
    var failure: ((String) -> Void)?

    func start(onSnapshot: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        snapshot = onSnapshot
        failure = onFailure
        respond()
    }
    func request(_ payload: [String: String]) { requests.append(payload) }
    func stop() {}
    func respond(id: String? = nil, error: String? = nil, result: String? = nil) {
        var reply: [String: Any] = ["node": "test@127.0.0.1", "peers": [], "messages": [],
                                   "connection_string": "parvi://connect/v1?node=test&cookie=test",
            "swarms": [
                ["id": "one", "name": "Music", "invitation": "invite-one", "members": ["test@127.0.0.1", "peer-a"], "messages": []],
                ["id": "two", "name": "Another room", "invitation": "invite-two", "members": ["test@127.0.0.1", "peer-b"], "messages": []]
            ],
            "network": ["nodes": [
                ["id": "test@127.0.0.1", "state": "running", "detail": "responsive"],
                ["id": "peer-a", "state": "running", "detail": "responsive"],
                ["id": "peer-b", "state": "running", "detail": "responsive"]
            ], "edges": [["test@127.0.0.1", "peer-a"], ["test@127.0.0.1", "peer-b"]]]]
        if let result { reply["result"] = ["swarm_id": result] }
        if let id { reply["request_id"] = id }
        if let error { reply["error"] = error }
        snapshot?(try! JSONSerialization.data(withJSONObject: reply))
    }
}

final class ChatModelTests: XCTestCase {
    func testRejectedSendKeepsDraftAndUnrelatedSnapshotCannotAcknowledgeIt() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let connected = ChatModel(runtime: runtime)
            connected.draft = "Please keep this"
            connected.send()
            XCTAssertTrue(connected.sending)
            runtime.respond()
            XCTAssertTrue(connected.sending)
            XCTAssertEqual(connected.draft, "Please keep this")
            runtime.respond(id: runtime.requests.last!["request_id"], error: "Worker unavailable")
            XCTAssertFalse(connected.sending)
            XCTAssertEqual(connected.draft, "Please keep this")
            XCTAssertEqual(connected.error, "Worker unavailable")
        }
    }

    func testSuccessfulSendDoesNotEraseNewerDraft() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            model.draft = "First message"
            model.send()
            model.draft = "Next message"
            runtime.respond(id: runtime.requests.last!["request_id"])
            XCTAssertEqual(model.draft, "Next message")
            XCTAssertFalse(model.sending)
            model.send()
            runtime.respond(id: runtime.requests.last!["request_id"])
            XCTAssertEqual(model.draft, "")
        }
    }

    func testJoinUsesSingleStringAndRetainsRejectedInvitation() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            model.incomingInvitation = "  invalid invitation  "
            model.join()
            XCTAssertEqual(runtime.requests.last?["invitation"], "invalid invitation")
            XCTAssertTrue(model.joining)
            runtime.respond(id: runtime.requests.last!["request_id"], error: "Invalid invitation")
            XCTAssertEqual(model.incomingInvitation, "  invalid invitation  ")
            XCTAssertEqual(model.joinError, "Invalid invitation")
            XCTAssertTrue(model.canJoin)
            model.join()
            runtime.respond(id: runtime.requests.last!["request_id"])
            XCTAssertEqual(model.incomingInvitation, "")
            XCTAssertNil(model.joinError)
            XCTAssertNotNil(model.joinNotice)
        }
    }

    func testRuntimeFailureRetainsDraftAndDisablesAdmission() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            model.draft = "Unsent"
            model.send()
            runtime.failure?("Stopped")
            XCTAssertFalse(model.running)
            XCTAssertFalse(model.sending)
            XCTAssertFalse(model.canInvite)
            XCTAssertEqual(model.invitation, "")
            XCTAssertEqual(model.draft, "Unsent")
        }
    }
    func testDraftsAndAcknowledgementsAreScopedToTheirSwarm() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            model.draft = "Draft for one"
            model.selectedSwarmID = "two"
            XCTAssertEqual(model.draft, "")
            model.draft = "Message for two"
            model.send()
            XCTAssertEqual(runtime.requests.last?["swarm_id"], "two")
            model.selectedSwarmID = "one"
            XCTAssertEqual(model.draft, "Draft for one")
            XCTAssertFalse(model.sending)
            runtime.respond(id: runtime.requests.last!["request_id"])
            XCTAssertEqual(model.draft, "Draft for one")
            model.selectedSwarmID = "two"
            XCTAssertEqual(model.draft, "")
        }
    }

    func testGraphAndInvitationsBelongToSelectedSwarm() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            XCTAssertEqual(model.invitation, "invite-one")
            XCTAssertEqual(Set(model.network.nodes.map(\.id)), ["test@127.0.0.1", "peer-a"])
            XCTAssertEqual(model.network.edges, [["test@127.0.0.1", "peer-a"]])
            model.selectedSwarmID = "two"
            XCTAssertEqual(model.invitation, "invite-two")
            XCTAssertEqual(Set(model.network.nodes.map(\.id)), ["test@127.0.0.1", "peer-b"])
            XCTAssertEqual(model.network.edges, [["test@127.0.0.1", "peer-b"]])
        }
    }

    func testAddingExistingSwarmSelectsItAndMembershipActionsCaptureScope() async {
        await MainActor.run {
            let runtime = TestRuntime()
            let model = ChatModel(runtime: runtime)
            model.incomingInvitation = "invite-two"
            model.join()
            runtime.respond(id: runtime.requests.last!["request_id"], result: "two")
            XCTAssertEqual(model.selectedSwarmID, "two")
            model.removeBoth(swarmID: "two", target: "peer-b")
            XCTAssertEqual(runtime.requests.last?["swarm_id"], "two")
            XCTAssertEqual(runtime.requests.last?["target"], "peer-b")
            model.selectedSwarmID = "one"
            runtime.respond(id: runtime.requests.last!["request_id"])
            XCTAssertEqual(model.selectedSwarmID, "one")
            model.leaveSwarm("one")
            XCTAssertEqual(runtime.requests.last?["method"], "leave_swarm")
            XCTAssertEqual(runtime.requests.last?["swarm_id"], "one")
        }
    }

}
