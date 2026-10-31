import Foundation
import XCTest
@testable import YunleFun

private let initialRestoreNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Local account actors and the actual launch coordinators. These tests do not
/// create a WebView, contact an account service, or claim a UI launch occurred.
@MainActor
final class AccountInitialRestoreTests: XCTestCase {
    func testEarlyInvitationWithCachedPlayWaitsForReservedRestoreAndResolvesOnce() async throws {
        let gate = InitialRestoreGate()
        let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a")
        let store = try makeStore(ids: ["a"], activeID: "a", api: api)
        XCTAssertEqual(store.initialRestorePhase, .unprepared)
        await store.consumeInitialRestore()
        XCTAssertEqual(store.initialRestorePhase, .unprepared, "Consumption cannot invent an unprepared startup")
        let beforePrepare = store.selectionOperationGeneration
        store.prepareInitialRestore()
        let reserved = store.selectionOperationGeneration
        XCTAssertNotEqual(reserved, beforePrepare)
        XCTAssertEqual(store.initialRestorePhase, .pending)
        XCTAssertFalse(store.isRestoring, "This tap arrives before the async task starts")
        XCTAssertTrue(store.isInitialRestorePending)
        store.prepareInitialRestore()
        XCTAssertEqual(store.selectionOperationGeneration, reserved)

        let action = try invitation()
        var deferred = NativeGameDeferredLaunchCoordinator()
        deferred.enqueue(action, boundary: boundary(store), selectionGeneration: reserved, isRestoring: restoring(store))
        XCTAssertEqual(take(&deferred, store), .waiting, "A cached Play entry cannot bypass the initial pending gate")
        let login = NativeGameLoginCoordinator()
        login.begin(action, origin: boundary(store), isRestoring: restoring(store))
        XCTAssertNil(login.login, "Do not present guest login before the saved account is known")

        let first = Task { @MainActor in await store.consumeInitialRestore() }
        addTeardownBlock { first.cancel(); await gate.open(); await first.value }
        try await waitForEntry(gate)
        XCTAssertEqual(store.initialRestorePhase, .restoring)
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(store.selectionOperationGeneration, reserved, "Consuming must not reserve a second selection boundary")
        XCTAssertEqual(take(&deferred, store), .waiting)
        let duplicate = Task { @MainActor in await store.consumeInitialRestore() }
        store.prepareInitialRestore()
        await gate.open()
        await first.value
        await duplicate.value
        XCTAssertEqual(store.initialRestorePhase, .settled)
        XCTAssertFalse(restoring(store))
        XCTAssertEqual(take(&deferred, store), .launch(action))
        XCTAssertEqual(take(&deferred, store), .waiting)
        await store.consumeInitialRestore()
        store.prepareInitialRestore()
        XCTAssertEqual(store.selectionOperationGeneration, reserved)
        let reads = await api.userTokens
        XCTAssertEqual(reads, ["saved-a"], "Repeated prepare/consume may refresh the saved profile only once")
    }

    func testAnonymousSettlementCannotPassAnOldCatalogWaitToALaterLogin() async throws {
        let api = InitialRestoreAPI()
        let store = try makeStore(api: api)
        store.prepareInitialRestore()
        var deferred = NativeGameDeferredLaunchCoordinator()
        deferred.enqueue(try invitation(), boundary: boundary(store), selectionGeneration: store.selectionOperationGeneration,
                         isRestoring: restoring(store))
        await store.consumeInitialRestore()
        XCTAssertNil(store.user)
        XCTAssertEqual(store.initialRestorePhase, .settled)
        XCTAssertEqual(take(&deferred, store, hasPlay: false), .waiting, "Close restore adoption while the catalog is still unavailable")
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(take(&deferred, store), .discarded, "An unrelated later login cannot inherit the anonymous invitation")
        let reads = await api.userTokens
        XCTAssertEqual(reads, ["login-a"])
    }

    func testManualSameUIDSelectionAndAccountRoundTripInvalidateTheReservation() async throws {
        for selections in [["a"], ["b"], ["b", "a"]] {
            let api = InitialRestoreAPI()
            let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api)
            store.prepareInitialRestore()
            let reserved = store.selectionOperationGeneration
            var deferred = NativeGameDeferredLaunchCoordinator()
            deferred.enqueue(try invitation(), boundary: boundary(store), selectionGeneration: reserved, isRestoring: true)
            for id in selections { try await store.select(id) }
            XCTAssertNotEqual(store.selectionOperationGeneration, reserved)
            XCTAssertEqual(store.initialRestorePhase, .settled)
            XCTAssertEqual(store.user?.id, selections.last)
            let before = await api.userTokens
            await store.consumeInitialRestore()
            store.prepareInitialRestore()
            let after = await api.userTokens
            XCTAssertEqual(after, before, "A late startup cannot perform an extra profile restore after manual selection")
            XCTAssertEqual(take(&deferred, store), .discarded)
        }
    }

    func testManualRemoveCancelPasswordAndVerificationExpirePendingOrPreventLatePreparation() async throws {
        for prepareFirst in [false, true] {
            for operation in InitialRestoreManualOperation.allCases {
                let api = InitialRestoreAPI()
                let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api)
                if prepareFirst { store.prepareInitialRestore() }
                let original = store.selectionOperationGeneration
                var deferred = NativeGameDeferredLaunchCoordinator()
                deferred.enqueue(try invitation(), boundary: boundary(store), selectionGeneration: original,
                                 isRestoring: restoring(store))
                try await perform(operation, on: store)
                let manual = store.selectionOperationGeneration
                XCTAssertNotEqual(manual, original, "Even an anonymous cancellation is a new selection operation")
                let before = await api.userTokens
                store.prepareInitialRestore()
                await store.consumeInitialRestore()
                XCTAssertEqual(store.initialRestorePhase, .settled)
                XCTAssertFalse(store.isInitialRestorePending)
                XCTAssertEqual(store.selectionOperationGeneration, manual)
                let after = await api.userTokens
                XCTAssertEqual(after, before, "Startup cannot run after \(operation), prepareFirst=\(prepareFirst)")
                XCTAssertEqual(take(&deferred, store), .discarded)
                if operation == .remove { XCTAssertFalse(store.overview.users.contains { $0.id == "a" }) }
            }
        }
    }

    func testManualLoginAlreadyInFlightIsNotInterruptedByLateInitialPreparation() async throws {
        let gate = InitialRestoreGate()
        let api = InitialRestoreAPI(gate: gate, gatedToken: "login-a")
        let store = try makeStore(api: api)
        let continuation = AccountSignInContinuation(requestID: UUID(), origin: boundary(store))
        var proof: AccountSignInSuccess?
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { proof = $0 })
        }
        addTeardownBlock { login.cancel(); await gate.open(); _ = try? await login.value }
        try await waitForEntry(gate)
        let manual = store.selectionOperationGeneration
        store.prepareInitialRestore()
        await store.consumeInitialRestore()
        XCTAssertEqual(store.initialRestorePhase, .settled)
        XCTAssertEqual(store.selectionOperationGeneration, manual)
        await gate.open()
        try await login.value
        XCTAssertEqual(store.user?.id, "a")
        let committed = try XCTUnwrap(proof)
        XCTAssertTrue(store.isCurrent(committed), "A late startup API must not expire an already-running manual login")
        let reads = await api.userTokens
        XCTAssertEqual(reads, ["login-a"])
    }

    func testRunningInitialRestoreCannotPublishOverNewOrSameUIDManualLogin() async throws {
        for target in ["a", "b"] {
            let gate = InitialRestoreGate()
            let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a")
            let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api)
            store.prepareInitialRestore()
            var deferred = NativeGameDeferredLaunchCoordinator()
            deferred.enqueue(try invitation(), boundary: boundary(store), selectionGeneration: store.selectionOperationGeneration,
                             isRestoring: true)
            let pending = Task { @MainActor in await store.consumeInitialRestore() }
            addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
            try await waitForEntry(gate)
            XCTAssertEqual(take(&deferred, store), .waiting)
            try await store.passwordSignIn(identifier: target, password: "fixture", captcha: nil)
            let accepted = store.overview
            let generation = store.selectionOperationGeneration
            XCTAssertEqual(store.initialRestorePhase, .settled)
            await gate.open()
            await pending.value
            XCTAssertEqual(store.overview, accepted, "The saved profile result cannot overwrite the replacement login")
            XCTAssertEqual(store.user?.name, "profile:login-\(target)")
            XCTAssertEqual(store.selectionOperationGeneration, generation)
            XCTAssertNil(store.notice)
            XCTAssertEqual(take(&deferred, store), .discarded)
            let before = await api.userTokens
            await store.consumeInitialRestore()
            let after = await api.userTokens
            XCTAssertEqual(after, before)
        }
    }

    func testRunningSameUIDSelectionReconcilesBlockedAndFinallyExpiredSavedAccount() async throws {
        for failure in InitialRestoreProfileFailure.allCases {
            let gate = InitialRestoreGate()
            let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a", failure: failure)
            let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api)
            store.prepareInitialRestore()
            let pending = Task { @MainActor in await store.consumeInitialRestore() }
            addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
            try await waitForEntry(gate)
            try await store.select("a")
            let manual = store.selectionOperationGeneration
            XCTAssertEqual(store.user?.id, "a")
            XCTAssertTrue(store.isRestoring, "The manual same-UID selection does not start another profile restore")
            await gate.open()
            await pending.value

            XCTAssertNil(store.user, "The saved identity was invalidated by the authoritative \(failure) response")
            XCTAssertEqual(store.overview.users.map(\.id), ["b"])
            XCTAssertEqual(store.selectionOperationGeneration, manual)
            XCTAssertEqual(store.initialRestorePhase, .settled)
            XCTAssertFalse(restoring(store))
            let reads = await api.userTokens
            XCTAssertEqual(reads, failure == .expired ? ["saved-a", "login-a"] : ["saved-a"],
                           "Finishing may read the latest overview but must not perform a new profile restore")
        }
    }

    func testCancelledInitialRestoreStillReconcilesAnAuthoritativeBlockedRemoval() async throws {
        for selectAgain in [false, true] {
            let gate = InitialRestoreGate()
            let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a", failure: .blocked)
            let store = try makeStore(ids: ["a"], activeID: "a", api: api)
            store.prepareInitialRestore()
            let pending = Task { @MainActor in await store.consumeInitialRestore() }
            addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
            try await waitForEntry(gate)
            if selectAgain { try await store.select("a") }
            pending.cancel()
            // This API deliberately ignores cancellation: its definitive reply
            // has already reached the account actor and invalidates the record.
            await gate.open()
            await pending.value
            XCTAssertNil(store.user)
            XCTAssertTrue(store.overview.users.isEmpty)
            XCTAssertEqual(store.initialRestorePhase, .settled)
            XCTAssertFalse(restoring(store))
            let reads = await api.userTokens
            XCTAssertEqual(reads, ["saved-a"])
        }
    }

    func testOldInvalidProfileCannotReplaceDifferentManualSelectionOrLogin() async throws {
        for failure in InitialRestoreProfileFailure.allCases {
            for login in [false, true] {
                let gate = InitialRestoreGate()
                let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a", failure: failure)
                let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api)
                store.prepareInitialRestore()
                let pending = Task { @MainActor in await store.consumeInitialRestore() }
                addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
                try await waitForEntry(gate)
                if login { try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil) }
                else { try await store.select("b") }
                let accepted = store.overview
                let manual = store.selectionOperationGeneration
                await gate.open()
                await pending.value
                XCTAssertEqual(store.overview, accepted)
                XCTAssertEqual(store.user?.id, "b")
                XCTAssertEqual(store.selectionOperationGeneration, manual)
                XCTAssertNil(store.notice)
                XCTAssertFalse(restoring(store))
                let reads = await api.userTokens
                XCTAssertEqual(reads, login ? ["saved-a", "login-b"] : ["saved-a"])
            }
        }
    }

    func testReconciliationAwaitCannotPublishAcrossASelectionOrLoginBoundary() async throws {
        for login in [false, true] {
            let response = InitialRestoreGate()
            let reconciliation = InitialRestoreGate()
            let api = InitialRestoreAPI(gate: response, gatedToken: "saved-a", failure: .blocked)
            let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api,
                                      initialRestoreReconciliationOverview: { session in
                let snapshot = try await session.overview()
                await reconciliation.wait()
                return snapshot
            })
            store.prepareInitialRestore()
            let pending = Task { @MainActor in await store.consumeInitialRestore() }
            addTeardownBlock {
                pending.cancel(); await response.open(); await reconciliation.open(); await pending.value
            }
            try await waitForEntry(response)
            try await store.select("a")
            await response.open()
            try await waitForEntry(reconciliation)
            XCTAssertEqual(store.user?.id, "a", "The fresh nil-identity snapshot is held before Store publication")
            if login { try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil) }
            else { try await store.select("b") }
            let accepted = store.overview
            let manual = store.selectionOperationGeneration
            await reconciliation.open()
            await pending.value
            XCTAssertEqual(store.overview, accepted, "The held overview belongs to the previous selection")
            XCTAssertEqual(store.user?.id, "b")
            XCTAssertEqual(store.selectionOperationGeneration, manual)
            XCTAssertNil(store.notice)
            XCTAssertEqual(store.initialRestorePhase, .settled)
            XCTAssertFalse(restoring(store))
            let reads = await api.userTokens
            XCTAssertEqual(reads, login ? ["saved-a", "login-b"] : ["saved-a"])
        }
    }

    func testReconciliationDoesNotPublishAheadOfAManualGuestLoginProof() async throws {
        let response = InitialRestoreGate()
        let publication = InitialRestoreGate()
        let api = InitialRestoreAPI(gate: response, gatedToken: "saved-a", failure: .blocked)
        let store = try makeStore(ids: ["a"], activeID: "a", api: api, signInOverview: { session, commit in
            let accepted = try await session.overview(matching: commit)
            await publication.wait()
            return accepted
        })
        store.prepareInitialRestore()
        let pending = Task { @MainActor in await store.consumeInitialRestore() }
        addTeardownBlock { pending.cancel(); await response.open(); await pending.value }
        try await waitForEntry(response)
        try await store.remove("a")
        let continuation = AccountSignInContinuation(requestID: UUID(), origin: boundary(store))
        var proof: AccountSignInSuccess?
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { proof = $0 })
        }
        addTeardownBlock { login.cancel(); await publication.open(); _ = try? await login.value }
        try await waitForEntry(publication)
        await response.open()
        await pending.value
        XCTAssertNil(store.user, "The login owns the atomic publication of identity and continuation proof")
        XCTAssertNil(proof)
        XCTAssertFalse(restoring(store))
        await publication.open()
        try await login.value
        XCTAssertEqual(store.user?.id, "b")
        let committed = try XCTUnwrap(proof)
        XCTAssertTrue(store.isCurrent(committed))
    }

    func testFailedReconciliationSettlesWithoutReplacingAManualIdentityOrNotice() async throws {
        let response = InitialRestoreGate()
        let reconciliation = InitialRestoreGate()
        let api = InitialRestoreAPI(gate: response, gatedToken: "saved-a")
        let store = try makeStore(ids: ["a", "b"], activeID: "a", api: api,
                                  initialRestoreReconciliationOverview: { _ in
            await reconciliation.wait()
            throw URLError(.notConnectedToInternet)
        })
        store.prepareInitialRestore()
        let pending = Task { @MainActor in await store.consumeInitialRestore() }
        addTeardownBlock {
            pending.cancel(); await response.open(); await reconciliation.open(); await pending.value
        }
        try await waitForEntry(response)
        await response.open()
        try await waitForEntry(reconciliation)
        try await store.select("b")
        let accepted = store.overview
        await reconciliation.open()
        await pending.value
        XCTAssertEqual(store.overview, accepted)
        XCTAssertEqual(store.user?.id, "b")
        XCTAssertNil(store.notice, "An old finishing task cannot replace the manual operation's notice")
        XCTAssertEqual(store.initialRestorePhase, .settled)
        XCTAssertFalse(restoring(store))
    }

    func testFailedOrCancelledInteractiveCallReconcilesSavedAuthorityWithoutAnotherRestore() async throws {
        for verification in [false, true] {
            for cancel in [false, true] {
                let authentication = InitialRestoreGate()
                let api = InitialRestoreAPI(signInGates: ["b": authentication], failedSignInIDs: cancel ? [] : ["b"])
                let store = try makeStore(ids: ["a"], activeID: "a", api: api)
                XCTAssertNil(store.user, "The saved actor identity has not yet been published")
                let login = Task { @MainActor in try await self.signIn("b", verification: verification, on: store) }
                addTeardownBlock { login.cancel(); await authentication.open(); _ = try? await login.value }
                try await waitForEntry(authentication)
                if cancel { login.cancel() }
                await authentication.open()
                do { try await login.value; XCTFail("The fixture must preserve the original sign-in failure") }
                catch {
                    if cancel { XCTAssertTrue(error is CancellationError) }
                    else { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
                }
                XCTAssertEqual(store.user?.id, "a")
                XCTAssertEqual(store.user?.name, "saved:a", "Reconciliation reads local authority without a profile request")
                XCTAssertFalse(store.overview.users.contains { $0.id == "b" })
                let reads = await api.userTokens
                XCTAssertEqual(reads, cancel ? ["login-b"] : [])
            }
        }
    }

    func testFailedInteractiveReconciliationCannotPublishAcrossANewerLogin() async throws {
        let reconciliation = InitialRestoreGate()
        let api = InitialRestoreAPI(failedSignInIDs: ["b"])
        let store = try makeStore(ids: ["a"], activeID: "a", api: api,
                                  initialRestoreReconciliationOverview: { session in
            let snapshot = try await session.overview()
            await reconciliation.wait()
            return snapshot
        })
        let failed = Task { @MainActor in try await self.signIn("b", verification: false, on: store) }
        addTeardownBlock { failed.cancel(); await reconciliation.open(); _ = try? await failed.value }
        try await waitForEntry(reconciliation)
        try await store.passwordSignIn(identifier: "c", password: "fixture", captcha: nil)
        let accepted = store.overview
        let selected = store.selectionOperationGeneration
        await reconciliation.open()
        do { try await failed.value; XCTFail("The failed call must still throw its original error") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(store.overview, accepted)
        XCTAssertEqual(store.user?.id, "c")
        XCTAssertEqual(store.selectionOperationGeneration, selected)
        XCTAssertNil(store.notice)
        let reads = await api.userTokens
        XCTAssertEqual(reads, ["login-c"])
    }

    func testExplicitCancellationPublishesFreshSavedAuthorityWithoutAProfileRestore() async throws {
        let api = InitialRestoreAPI()
        let store = try makeStore(ids: ["a"], activeID: "a", api: api)
        XCTAssertNil(store.user)
        let original = store.selectionOperationGeneration
        await store.cancelSignIn()
        XCTAssertNotEqual(store.selectionOperationGeneration, original)
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(store.user?.name, "saved:a")
        let reads = await api.userTokens
        XCTAssertTrue(reads.isEmpty)
    }

    func testCancelledStartupBeforeConsumptionSettlesWithoutProfileRequest() async throws {
        let gate = InitialRestoreGate()
        let api = InitialRestoreAPI()
        let store = try makeStore(ids: ["a"], activeID: "a", api: api)
        store.prepareInitialRestore()
        let pending = Task { @MainActor in
            await gate.wait()
            await store.consumeInitialRestore()
        }
        addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
        try await waitForEntry(gate)
        pending.cancel()
        await gate.open()
        await pending.value
        XCTAssertEqual(store.initialRestorePhase, .settled)
        XCTAssertFalse(restoring(store))
        let reads = await api.userTokens
        XCTAssertTrue(reads.isEmpty)
    }

    func testFailedOrCancelledRunningStartupAlwaysEndsThePendingGate() async throws {
        for cancel in [false, true] {
            let gate = InitialRestoreGate()
            let api = InitialRestoreAPI(gate: gate, gatedToken: "saved-a", failUser: !cancel)
            let store = try makeStore(ids: ["a"], activeID: "a", api: api)
            store.prepareInitialRestore()
            let pending = Task { @MainActor in await store.consumeInitialRestore() }
            addTeardownBlock { pending.cancel(); await gate.open(); await pending.value }
            try await waitForEntry(gate)
            if cancel { pending.cancel() }
            await gate.open()
            await pending.value
            XCTAssertEqual(store.initialRestorePhase, .settled)
            XCTAssertFalse(restoring(store))
            await store.consumeInitialRestore()
            let reads = await api.userTokens
            XCTAssertEqual(reads, ["saved-a"])
            if !cancel { XCTAssertNotNil(store.notice) }
        }
    }

    func testLateInteractiveCommitCannotProveAnExpiredGuestContinuation() async throws {
        let snapshots = InitialRestoreGate()
        let store = try makeStore(signInOverview: { session, commit in
            let accepted = try await session.overview(matching: commit)
            await snapshots.wait()
            return accepted
        })
        store.prepareInitialRestore()
        await store.consumeInitialRestore()
        let coordinator = NativeGameLoginCoordinator()
        coordinator.begin(try invitation(), origin: boundary(store), isRestoring: restoring(store))
        let intent = try XCTUnwrap(coordinator.login)
        coordinator.didPresent(intent.id)
        var proof: AccountSignInSuccess?
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: intent.continuation, onCommitted: { proof = $0 })
        }
        addTeardownBlock { login.cancel(); await snapshots.open(); _ = try? await login.value }
        try await waitForEntry(snapshots)
        await store.cancelSignIn()
        await store.consumeInitialRestore()
        await snapshots.open()
        do { try await login.value; XCTFail("A cancelled guest continuation cannot complete from a held snapshot") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertNil(proof)
        let unproven = AccountSignInSuccess(requestID: intent.id, attemptID: UUID(), origin: intent.origin,
                                           target: boundary(store))
        XCTAssertFalse(store.isCurrent(unproven))
        coordinator.committed(unproven, current: boundary(store), isUsable: store.user?.isUsable == true,
                              proofIsCurrent: store.isCurrent(unproven))
        coordinator.presentationEnded()
        XCTAssertNil(coordinator.consume(current: boundary(store), isUsable: store.user?.isUsable == true,
                                         proofIsCurrent: store.isCurrent(unproven)))
    }

    private func makeStore(ids: [String] = [], activeID: String? = nil, api: InitialRestoreAPI = InitialRestoreAPI(),
                           signInOverview: (@Sendable (AccountSession, AccountSignInCommit) async throws -> AccountOverview)? = nil,
                           initialRestoreReconciliationOverview: (@Sendable (AccountSession) async throws -> AccountOverview)? = nil) throws -> AccountStore {
        var saved = AccountVaultState()
        saved.activeID = activeID
        saved.accounts = ids.map { id in
            SavedAccount(user: AccountUser(id: id, name: "saved:\(id)"),
                         credential: AccountCredential(accessToken: "saved-\(id)", refreshToken: "refresh-\(id)",
                                                       expiresAt: initialRestoreNow.addingTimeInterval(3600)))
        }
        let vault = InitialRestoreVault(data: try JSONEncoder().encode(saved))
        return AccountStore(session: AccountSession(api: api, vault: vault, now: { initialRestoreNow }),
                            signInOverview: signInOverview,
                            initialRestoreReconciliationOverview: initialRestoreReconciliationOverview)
    }

    private func invitation() throws -> NativeGameLaunchIntent {
        .room(try NativeGameRoomIntent(input: "ABC234", role: .spectator))
    }
    private func boundary(_ store: AccountStore) -> AccountRequestBoundary {
        .init(uid: store.user?.id, generation: store.identityGeneration)
    }
    private func restoring(_ store: AccountStore) -> Bool { store.isRestoring || store.isInitialRestorePending }
    private func take(_ flow: inout NativeGameDeferredLaunchCoordinator, _ store: AccountStore,
                      hasPlay: Bool = true) -> NativeGameDeferredLaunchCoordinator.Resolution {
        flow.take(current: boundary(store), selectionGeneration: store.selectionOperationGeneration, isRestoring: restoring(store),
                  awaitingPresentationDismissal: false, hasPlay: hasPlay, catalogIsLoading: true)
    }
    private func perform(_ operation: InitialRestoreManualOperation, on store: AccountStore) async throws {
        switch operation {
        case .cancel: await store.cancelSignIn()
        case .remove: try await store.remove("a")
        case .password: try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil)
        case .verify:
            let challenge = VerificationChallenge(address: .email("fixture@example.invalid"), id: "b", isExistingUser: true,
                                                  expiresAt: initialRestoreNow.addingTimeInterval(60))
            try await store.verify(challenge, code: "123456", captcha: nil)
        }
    }
    private func signIn(_ id: String, verification: Bool, on store: AccountStore) async throws {
        if verification {
            let challenge = VerificationChallenge(address: .email("fixture@example.invalid"), id: id, isExistingUser: true,
                                                  expiresAt: initialRestoreNow.addingTimeInterval(60))
            try await store.verify(challenge, code: "123456", captcha: nil)
        } else {
            try await store.passwordSignIn(identifier: id, password: "fixture", captcha: nil)
        }
    }
    private func waitForEntry(_ gate: InitialRestoreGate) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await gate.entered { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The local fixture did not reach its explicit API gate")
        throw URLError(.timedOut)
    }
}

private enum InitialRestoreManualOperation: CaseIterable, Equatable { case cancel, remove, password, verify }
private enum InitialRestoreProfileFailure: CaseIterable { case blocked, expired }

private final class InitialRestoreVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    init(data: Data) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ value: Data) throws { lock.lock(); defer { lock.unlock() }; data = value }
}

private actor InitialRestoreGate {
    private(set) var entered = false
    private var opened = false
    private var held: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        if !opened { await withCheckedContinuation { held.append($0) } }
    }
    func open() { opened = true; held.forEach { $0.resume() }; held = [] }
}

private actor InitialRestoreAPI: AccountAuthenticating {
    private(set) var userTokens: [String] = []
    private(set) var passwordCount = 0
    private(set) var verificationCount = 0
    private let gate: InitialRestoreGate?
    private let gatedToken: String?
    private let failUser: Bool
    private let failure: InitialRestoreProfileFailure?
    private let signInGates: [String: InitialRestoreGate]
    private let failedSignInIDs: Set<String>
    init(gate: InitialRestoreGate? = nil, gatedToken: String? = nil, failUser: Bool = false,
         failure: InitialRestoreProfileFailure? = nil, signInGates: [String: InitialRestoreGate] = [:],
         failedSignInIDs: Set<String> = []) {
        self.gate = gate; self.gatedToken = gatedToken; self.failUser = failUser; self.failure = failure
        self.signInGates = signInGates; self.failedSignInIDs = failedSignInIDs
    }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        passwordCount += 1
        await signInGates[identifier]?.wait()
        if failedSignInIDs.contains(identifier) { throw URLError(.notConnectedToInternet) }
        return tokens(identifier)
    }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        verificationCount += 1
        await signInGates[challenge.id]?.wait()
        if failedSignInIDs.contains(challenge.id) { throw URLError(.notConnectedToInternet) }
        return tokens(challenge.id)
    }
    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        userTokens.append(accessToken)
        if accessToken == gatedToken { await gate?.wait() }
        if failUser { throw URLError(.notConnectedToInternet) }
        let id = String(accessToken.split(separator: "-").last!)
        if id == "a", let failure {
            if failure == .expired { throw AccountError.expiredSession }
            return AccountUser(id: id, name: "profile:\(accessToken)", status: "BLOCKED")
        }
        return AccountUser(id: id, name: "profile:\(accessToken)")
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        tokens(String(refreshToken.split(separator: "-").last!))
    }
    func signOut(accessToken: String, deviceID: String) async throws { }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.unavailable }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.unavailable }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.unavailable }
    private func tokens(_ id: String) -> AuthTokenResponse {
        AuthTokenResponse(accessToken: "login-\(id)", refreshToken: "refresh-\(id)", expiresIn: 3600, subject: id)
    }
}
