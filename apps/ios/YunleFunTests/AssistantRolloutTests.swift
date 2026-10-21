import XCTest
@testable import YunleFun

final class AssistantRolloutTests: XCTestCase {
    /// Account IDs whose stable buckets fall below and at-or-above 50.
    private lazy var low = (0..<500).map { "user-\($0)" }.first { AssistantRollout.bucket($0) < 50 }!
    private lazy var high = (0..<500).map { "user-\($0)" }.first { AssistantRollout.bucket($0) >= 50 }!

    func testEligibilityMatrix() {
        let cases: [(AssistantRollout.Audience, Int, String?, Bool?, Bool)] = [
            (.off, 100, "alice", true, false),
            (.off, 100, nil, nil, false),
            (.members, 100, "alice", true, true),
            (.members, 100, "alice", false, false),
            (.members, 100, "alice", nil, false),
            (.members, 100, nil, nil, false),
            (.signedIn, 100, "alice", false, true),
            (.signedIn, 100, "alice", nil, true),
            (.signedIn, 100, nil, nil, false),
            (.everyone, 100, nil, nil, true),
            (.everyone, 99, nil, nil, false),
            (.everyone, 100, "alice", false, true),
        ]
        for (audience, percent, user, member, expected) in cases {
            XCTAssertEqual(AssistantRollout(audience: audience, percent: percent).admits(userID: user, isMember: member), expected,
                           "\(audience) \(percent)% user=\(user ?? "guest") member=\(String(describing: member))")
        }
    }
    func testPercentageUsesAStableBucket() {
        for audience in [AssistantRollout.Audience.members, .signedIn, .everyone] {
            let half = AssistantRollout(audience: audience, percent: 50)
            XCTAssertTrue(half.admits(userID: low, isMember: true))
            XCTAssertFalse(half.admits(userID: high, isMember: true))
            XCTAssertFalse(AssistantRollout(audience: audience, percent: 0).admits(userID: low, isMember: true))
        }
        XCTAssertEqual(AssistantRollout.bucket("alice"), AssistantRollout.bucket("alice"))
        XCTAssertTrue((0..<100).contains(AssistantRollout.bucket("alice")))
    }
    func testParsesThePublicFeaturesPayload() throws {
        let parsed = try AssistantRollout(features: Data(#"{"assistant":{"audience":"signedIn","percent":30}}"#.utf8))
        XCTAssertEqual(parsed, AssistantRollout(audience: .signedIn, percent: 30))
        let unknown = try AssistantRollout(features: Data(#"{"assistant":{"audience":"all","percent":250}}"#.utf8))
        XCTAssertEqual(unknown, AssistantRollout(audience: .members, percent: 100))
        XCTAssertThrowsError(try AssistantRollout(features: Data("{}".utf8)))
    }
    @MainActor
    func testStoreCachesTheLastGoodValueAndKeepsItOnFailure() async throws {
        let suite = "assistant-rollout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let service = RolloutServiceFixture(result: .success(AssistantRollout(audience: .everyone, percent: 40)))
        let store = AssistantRolloutStore(defaults: defaults, service: service)
        XCTAssertEqual(store.rollout, .compiledDefault)
        await store.refresh(force: true)
        XCTAssertEqual(store.rollout, AssistantRollout(audience: .everyone, percent: 40))
        await service.set(.failure(URLError(.notConnectedToInternet)))
        await store.refresh(force: true)
        XCTAssertEqual(store.rollout, AssistantRollout(audience: .everyone, percent: 40))
        XCTAssertEqual(AssistantRolloutStore(defaults: defaults, service: service).rollout, AssistantRollout(audience: .everyone, percent: 40))
    }
}

private actor RolloutServiceFixture: AssistantRolloutServing {
    private var result: Result<AssistantRollout, Error>
    init(result: Result<AssistantRollout, Error>) { self.result = result }
    func set(_ result: Result<AssistantRollout, Error>) { self.result = result }
    func fetch() async throws -> AssistantRollout { try result.get() }
}
