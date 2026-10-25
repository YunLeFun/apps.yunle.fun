import Foundation

enum WorkshopError: Error, Equatable, AccountRequestFailure {
    case invalidInput, invalidResponse, unauthorized, forbidden, notFound, conflict, throttled, unavailable, identityChanged
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .invalidInput: return "请检查工坊编号、名称和内容长度。"
        case .invalidResponse: return "工坊返回的信息无法读取，请刷新后重试。"
        case .unauthorized: return "登录状态已失效，请重新登录。"
        case .forbidden: return "当前账号没有此权限，请刷新工坊状态。"
        case .notFound: return "这个工坊已不存在或暂不可访问。"
        case .conflict: return "工坊或坊客状态已变化，请刷新后再试。"
        case .throttled: return "操作较频繁，请稍后再试。"
        case .unavailable: return "暂时无法连接工坊，请检查网络后重试。"
        case .identityChanged: return "账号已变化，请重新打开此页面。"
        }
    }
    static func message(for error: Error) -> String {
        if let error = error as? WorkshopError { return error.message }
        if let error = error as? AccountError { return AccountError.message(for: error) }
        return WorkshopError.unavailable.message
    }
}
enum WorkshopJoinPolicy: String, Codable, CaseIterable, Identifiable {
    case approval, open, closed
    var id: String { rawValue }
    var label: String {
        switch self { case .approval: return "需要审批"; case .open: return "自由加入"; case .closed: return "停止加入" }
    }
}
enum WorkshopStatus: String, Codable, CaseIterable, Identifiable {
    case active, disabled
    var id: String { rawValue }
    var label: String { self == .active ? "开放中" : "已暂停" }
}
enum WorkshopAccess: String, Codable { case anonymous, none, pending, active, owner, blocked }
enum WorkshopMembershipStatus: String, Codable { case pending, active, rejected, left, removed, blocked }
struct PersonalWorkshop: Codable, Identifiable, Equatable {
    let id: String
    let ownerName: String
    let ownerAvatar: String?
    let name: String
    let description: String?
    let joinPolicy: WorkshopJoinPolicy
    let status: WorkshopStatus
    let ownerUid: String?
    enum CodingKeys: String, CodingKey { case id = "_id"; case ownerName, ownerAvatar, name, description, joinPolicy, status, ownerUid }
    var shareURL: URL { CatalogService.productionOrigin.appendingPathComponent("w/\(id)") }
    func validate(id: String? = nil, owner: String? = nil) throws {
        guard WorkshopLink.normalize(self.id) == self.id, id == nil || self.id == id,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 200,
              (description?.utf16.count ?? 0) <= 200, owner == nil || ownerUid == owner
        else { throw WorkshopError.invalidResponse }
    }
}
struct WorkshopMembership: Codable, Identifiable, Equatable {
    let workshopId: String
    let userUid: String
    let userName: String?
    let userAvatar: String?
    let status: WorkshopMembershipStatus
    let requestedAt: Double?
    let joinedAt: Double?
    let updatedAt: Double
    var id: String { userUid }
    var displayName: String { userName?.nilIfEmpty ?? "坊客" }
    func validate(workshopID: String, uid: String? = nil, status: WorkshopMembershipStatus? = nil) throws {
        guard workshopId == workshopID, !userUid.isEmpty, userUid.utf16.count <= 256,
              uid == nil || userUid == uid, status == nil || self.status == status,
              CommunityValue.timestamp(updatedAt), requestedAt.map(CommunityValue.timestamp) ?? true,
              joinedAt.map(CommunityValue.timestamp) ?? true else { throw WorkshopError.invalidResponse }
    }
}
struct WorkshopManagement: Decodable, Equatable {
    var workshop: PersonalWorkshop
    var pending: [WorkshopMembership]
    var guests: [WorkshopMembership]
    var blocked: [WorkshopMembership]
    func validate(owner: String) throws {
        try workshop.validate(owner: owner)
        let all = pending + guests + blocked
        guard Set(all.map(\.userUid)).count == all.count, all.allSatisfy({ $0.userUid != owner }) else { throw WorkshopError.invalidResponse }
        for (rows, status) in [(pending, WorkshopMembershipStatus.pending), (guests, .active), (blocked, .blocked)] {
            for row in rows { try row.validate(workshopID: workshop.id, status: status) }
        }
    }
    func member(_ uid: String) -> WorkshopMembership? { (pending + guests + blocked).first { $0.userUid == uid } }
    mutating func apply(_ member: WorkshopMembership) {
        pending.removeAll { $0.userUid == member.userUid }; guests.removeAll { $0.userUid == member.userUid }
        blocked.removeAll { $0.userUid == member.userUid }
        switch member.status { case .pending: pending.append(member); case .active: guests.append(member); case .blocked: blocked.append(member); default: break }
    }
}
struct WorkshopPage: Decodable {
    let surface: String
    let access: WorkshopAccess
    let workshop: PersonalWorkshop
    var apps: [CloudApplication]
    var permitsApps: Bool { workshop.status == .active && (access == .owner || access == .active) }
    func validate(id: String, identity: AuthorizedAccount?) throws {
        try workshop.validate(id: id)
        guard surface == "workshop", identity != nil || access == .anonymous,
              identity == nil || access != .anonymous,
              permitsApps || apps.isEmpty, Set(apps.map(\.id)).count == apps.count,
              apps.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && ($0.audience == "public" || $0.audience == "workshop") })
        else { throw WorkshopError.invalidResponse }
    }
}
struct WorkshopJoinResult: Decodable {
    let status: WorkshopMembershipStatus
    let joined: Bool
    func validate() throws {
        guard (status == .active || status == .pending), joined == (status == .active) else { throw WorkshopError.invalidResponse }
    }
}
struct WorkshopDraft: Equatable {
    var name = ""
    var description = ""
    var joinPolicy = WorkshopJoinPolicy.approval
    var status = WorkshopStatus.active
    init() {}
    init(_ workshop: PersonalWorkshop) {
        name = workshop.name; description = workshop.description ?? ""; joinPolicy = workshop.joinPolicy; status = workshop.status
    }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf16.count <= 40 && description.utf16.count <= 200
    }
}
enum WorkshopDecision: String, CaseIterable, Identifiable {
    case approve, reject, remove, block, unblock
    var id: String { rawValue }
    var label: String {
        switch self { case .approve: return "通过申请"; case .reject: return "拒绝申请"; case .remove: return "移出工坊"; case .block: return "禁止加入"; case .unblock: return "解除禁止" }
    }
    var result: WorkshopMembershipStatus {
        switch self { case .approve: return .active; case .reject: return .rejected; case .remove, .unblock: return .removed; case .block: return .blocked }
    }
    func allows(_ status: WorkshopMembershipStatus) -> Bool {
        switch self { case .approve, .reject: return status == .pending; case .remove: return status == .active
        case .block: return status == .active || status == .pending; case .unblock: return status == .blocked }
    }
}
