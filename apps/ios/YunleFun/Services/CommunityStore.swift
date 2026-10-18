import Combine
import Foundation

@MainActor
final class ReviewsStore: ObservableObject {
    @Published private var payload: ReviewList?
    @Published private var owned: AppReview?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    let appKey: String
    private let access: AccountRequestAccess<CommunityError>
    private let service: CommunityServing
    private var loadedBoundary: AccountRequestBoundary?
    private var loadID = UUID()
    private var writeID: UUID?

    init(appKey: String, accounts: IdentityScopedAccountAuthorizing, service: CommunityServing = CommunityService()) {
        self.appKey = appKey; access = AccountRequestAccess<CommunityError>(accounts: accounts); self.service = service
    }
    var summary: ReviewSummary? { payload?.summary }
    var reviews: [AppReview] { payload?.reviews ?? [] }
    var myReview: AppReview? {
        guard let loadedBoundary, access.isCurrent(loadedBoundary) else { return nil }
        return owned
    }
    func identityChanged() {
        loadID = UUID(); writeID = nil; loadedBoundary = nil; owned = nil
        if let payload { self.payload = ReviewList(summary: payload.summary, reviews: payload.reviews, myReview: nil) }
        isLoading = false; isSubmitting = false; error = nil; notice = nil
    }
    func refresh() async {
        let boundary = access.boundary, requestID = UUID()
        loadID = requestID; isLoading = true; error = nil
        defer { if loadID == requestID { isLoading = false } }
        do {
            let result: ReviewList
            if boundary.uid == nil { result = try await service.reviews(appKey: appKey, identity: nil) }
            else {
                result = try await access.perform(boundary: boundary) { identity in
                    try await self.service.reviews(appKey: self.appKey, identity: identity)
                }
            }
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            payload = result; owned = result.myReview; loadedBoundary = boundary
        } catch {
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            self.error = (error as? CommunityError)?.message ?? "无法载入评价，请检查网络后重试。"
        }
    }
    func submit(_ draft: ReviewDraft, generation: UUID) async throws -> ReviewStatus {
        guard access.boundary.generation == generation else { throw CommunityError.identityChanged }
        guard !isSubmitting else { throw CommunityError.throttled }
        let boundary = access.boundary, operationID = UUID()
        loadID = UUID(); isLoading = false
        writeID = operationID; isSubmitting = true
        defer { if writeID == operationID { isSubmitting = false; writeID = nil } }
        let result = try await access.perform(boundary: boundary) { identity in
            try await self.service.submit(appKey: self.appKey, draft: draft, identity: identity)
        }
        guard writeID == operationID else { throw CommunityError.identityChanged }
        owned = result.review
        loadedBoundary = boundary
        notice = result.status.message
        return result.status
    }
    func deleteMine(expectedID: String, generation: UUID) async throws {
        guard access.boundary.generation == generation else { throw CommunityError.identityChanged }
        guard !isSubmitting, let review = myReview, review.id == expectedID else { throw CommunityError.invalidInput }
        let boundary = access.boundary, operationID = UUID()
        loadID = UUID(); isLoading = false
        writeID = operationID; isSubmitting = true
        defer { if writeID == operationID { isSubmitting = false; writeID = nil } }
        try await access.perform(boundary: boundary) { identity in try await self.service.delete(reviewID: review.id, identity: identity) }
        guard writeID == operationID else { throw CommunityError.identityChanged }
        owned = nil
        if let payload {
            self.payload = ReviewList(summary: payload.summary, reviews: payload.reviews.filter { $0.id != review.id }, myReview: nil)
        }
        notice = "评价已删除"
        await refresh()
    }
    func report(target: ReportTarget, reason: ReportReason, detail: String, generation: UUID) async throws {
        guard access.boundary.generation == generation else { throw CommunityError.identityChanged }
        guard target.appKey == appKey else { throw CommunityError.invalidInput }
        guard !isSubmitting else { throw CommunityError.throttled }
        let boundary = access.boundary, operationID = UUID()
        writeID = operationID; isSubmitting = true
        defer { if writeID == operationID { isSubmitting = false; writeID = nil } }
        try await access.perform(boundary: boundary) { identity in
            try await self.service.report(target: target, reason: reason, detail: detail, identity: identity)
        }
        guard writeID == operationID else { throw CommunityError.identityChanged }
        notice = "举报已提交，可在“我的举报”查看处理状态。"
    }
}

@MainActor
final class MyReportsStore: ObservableObject {
    @Published private var records: [MyReport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let access: AccountRequestAccess<CommunityError>
    private let service: CommunityServing
    private var loadedBoundary: AccountRequestBoundary?
    private var loadID = UUID()
    init(accounts: IdentityScopedAccountAuthorizing, service: CommunityServing = CommunityService()) {
        access = AccountRequestAccess<CommunityError>(accounts: accounts); self.service = service
    }
    var reports: [MyReport] {
        guard let loadedBoundary, access.isCurrent(loadedBoundary) else { return [] }
        return records
    }
    var hasLoaded: Bool { loadedBoundary.map(access.isCurrent) ?? false }
    func refresh() async {
        let boundary = access.boundary, requestID = UUID()
        loadID = requestID; isLoading = true; error = nil
        defer { if loadID == requestID { isLoading = false } }
        guard boundary.uid != nil else { records = []; loadedBoundary = nil; return }
        do {
            let result = try await access.perform(boundary: boundary) { try await self.service.reports(identity: $0) }
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            records = result; loadedBoundary = boundary
        } catch {
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            self.error = (error as? CommunityError)?.message ?? "无法载入举报记录，请检查网络后重试。"
        }
    }
}
