import XCTest
@testable import YunleFun

@MainActor
final class HomeLibraryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testPersistsOrderAndRecentUseWithoutMixingAccounts() {
        let a = CloudApplication(id: "a", name: "应用 A")
        let b = CloudApplication(id: "b", name: "应用 B")
        let first = HomeLibrary(directory: directory, accountID: "account/one")
        first.add(a)
        first.add(b)
        first.add(a)
        first.move(from: IndexSet(integer: 0), to: 2)
        first.recordUse(a)
        first.recordUse(b)
        first.recordUse(a)
        XCTAssertEqual(first.snapshot.applications.map(\.id), ["b", "a"])
        XCTAssertEqual(first.snapshot.recentIDs, ["a", "b"])
        let restored = HomeLibrary(directory: directory, accountID: "account/one")
        XCTAssertEqual(restored.snapshot, first.snapshot)
        XCTAssertTrue(HomeLibrary(directory: directory, accountID: "account/two").snapshot.applications.isEmpty)
        XCTAssertTrue(HomeLibrary(directory: directory).snapshot.applications.isEmpty)
    }

    func testCorruptDataIsReportedAndNeverOverwritten() throws {
        let library = HomeLibrary(directory: directory)
        let original = Data("corrupt-but-preserved".utf8)
        try original.write(to: library.fileURL)
        let reopened = HomeLibrary(directory: directory)
        XCTAssertNotNil(reopened.storageError)
        reopened.add(CloudApplication(id: "new", name: "新应用"))
        XCTAssertEqual(try Data(contentsOf: library.fileURL), original)
    }

    func testRemovingAnApplicationRemovesItsRecentEntry() {
        let app = CloudApplication(id: "a", name: "应用")
        let library = HomeLibrary(directory: directory)
        library.add(app)
        library.recordUse(app)
        library.remove(app)
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertTrue(library.snapshot.recentIDs.isEmpty)
    }

    func testAccountSwitchClearsProjectionAndRestoresOnlyTheSelectedNamespace() throws {
        let library = HomeLibrary(directory: directory)
        library.add(CloudApplication(id: "guest", name: "访客应用"))
        library.activateAccount("a")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        library.add(CloudApplication(id: "private-a", name: "A 的应用"))
        library.activateAccount("b")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        try Data("corrupt".utf8).write(to: library.fileURL)
        library.activateAccount("a")
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["private-a"])
        library.activateAccount("b")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertNotNil(library.storageError)
        library.activateAccount(nil)
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["guest"])
        XCTAssertNil(library.storageError)
    }
}
