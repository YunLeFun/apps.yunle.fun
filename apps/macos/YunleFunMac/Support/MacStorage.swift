import Foundation

enum MacStorage {
    static var namespace: String { Bundle.main.bundleIdentifier ?? "fun.yunle.macos.dev" }
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(namespace, isDirectory: true)
    }
    static var catalogCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(namespace, isDirectory: true).appendingPathComponent("public-catalog.json")
    }
}
