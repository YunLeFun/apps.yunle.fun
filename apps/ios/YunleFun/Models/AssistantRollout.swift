import CryptoKit
import Foundation

/// Who sees the AI 助手 entry. The server still enforces membership on every request;
/// this only decides whether the entry is offered.
struct AssistantRollout: Equatable, Sendable {
    enum Audience: String, CaseIterable, Sendable { case off, members, signedIn, everyone }
    static let compiledDefault = AssistantRollout(audience: .members, percent: 100)
    let audience: Audience
    let percent: Int
    init(audience: Audience, percent: Int) {
        self.audience = audience; self.percent = min(100, max(0, percent))
    }
    /// Parses the public `/api/features` payload; unknown audiences fall back to members like the server does.
    init(features data: Data) throws {
        struct Payload: Decodable {
            struct Assistant: Decodable { let audience: String?; let percent: Double? }
            let assistant: Assistant
        }
        guard data.count <= 16 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        let assistant = try JSONDecoder().decode(Payload.self, from: data).assistant
        let percent = assistant.percent.flatMap { $0.isFinite ? Int($0.rounded(.down)) : nil } ?? 100
        self.init(audience: assistant.audience.flatMap(Audience.init(rawValue:)) ?? .members, percent: percent)
    }
    /// `userID` is nil for guests; `isMember` is nil while the membership snapshot is unknown,
    /// so a members-only entry stays hidden until it is known.
    func admits(userID: String?, isMember: Bool?) -> Bool {
        switch audience {
        case .off: return false
        case .members:
            guard let userID, isMember == true else { return false }
            return Self.bucket(userID) < percent
        case .signedIn:
            guard let userID else { return false }
            return Self.bucket(userID) < percent
        case .everyone:
            guard let userID else { return percent == 100 }
            return Self.bucket(userID) < percent
        }
    }
    /// A stable 0–99 bucket per account, so raising the percentage only adds accounts.
    static func bucket(_ userID: String) -> Int {
        let digest = SHA256.hash(data: Data(("assistant:" + userID).utf8))
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return Int(value % 100)
    }
}
