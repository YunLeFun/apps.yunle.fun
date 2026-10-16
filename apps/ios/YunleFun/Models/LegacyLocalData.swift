import CryptoKit
import Foundation

enum LegacyImportError: LocalizedError {
    case invalidData, unreadable, storage, identityChanged, alreadyClaimed, recordChanged
    var errorDescription: String? {
        switch self {
        case .invalidData: return "旧版记录的格式暂时无法导入，原记录已保留。"
        case .unreadable: return "暂时无法读取旧版记录，请稍后重试。"
        case .storage: return "未能保存导入记录，请检查设备存储空间后重试。"
        case .identityChanged: return "当前账号或云居已变化，请重新确认导入位置。"
        case .alreadyClaimed: return "这份旧版记录已为另一个云居保留，请切换到原来的账号后继续。"
        case .recordChanged: return "旧版记录已变化，请重新读取并确认导入内容。"
        }
    }
}

struct LegacyAccountHint: Codable, Equatable, Identifiable {
    let uid: String
    let nickname: String?
    var id: String { uid }
    var label: String { nickname?.nilIfEmpty ?? "旧版账号" }
}

/// Only noncredential keys are read. Unknown settings remain in the protected
/// archive until their native equivalents are available; they never grant access.
struct LegacyLocalData: Codable, Equatable {
    static let keys = ["ylf:homescreen-apps", "ylf:dock-apps", "ylf:recent-apps-v2", "ylf:homescreen-sync-at",
                       "ylf_theme_mode", "ylf:cloud-sync-enabled", "ylf:cloud-auto-sync", "ylf:dock-visible",
                       "ylf_icon_style", "ylf:preview-window-size", "ylf:in-app-browser-mode",
                       "ylf:external-link-mode", "ylf:session-limit-preference", "ylf_saved_accounts"]
    let values: [String: String]
    var id: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(values)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var appearance: String? { values["ylf_theme_mode"] }
    var syncEnabled: Bool? { boolean("ylf:cloud-sync-enabled") }
    var autoSyncEnabled: Bool? { boolean("ylf:cloud-auto-sync") }
    var dockVisible: Bool? { boolean("ylf:dock-visible") }
    var accounts: [LegacyAccountHint] { (try? decode([LegacyAccountHint].self, key: "ylf_saved_accounts")) ?? [] }
    var hasHome: Bool { ["ylf:homescreen-apps", "ylf:dock-apps", "ylf:recent-apps-v2"].contains { values[$0] != nil } }
    var hasOtherSettings: Bool {
        ["ylf_icon_style", "ylf:preview-window-size", "ylf:in-app-browser-mode", "ylf:external-link-mode", "ylf:session-limit-preference"].contains { values[$0] != nil }
    }
    var configuration: HomeConfiguration? {
        guard hasHome else { return nil }
        return try? HomeConfiguration(installedApps: decode([HomeAppReference].self, key: "ylf:homescreen-apps") ?? [],
                                      dockApps: decode([HomeAppReference].self, key: "ylf:dock-apps") ?? [],
                                      recentApps: decode([HomeRecentReference].self, key: "ylf:recent-apps-v2") ?? [],
                                      updatedAt: decode(Int64.self, key: "ylf:homescreen-sync-at") ?? 0)
    }
    init(values: [String: String]) throws {
        guard Set(values.keys).isSubset(of: Set(Self.keys)),
              values.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) <= 524_288 else { throw LegacyImportError.invalidData }
        var sanitized = values
        if let raw = values["ylf_saved_accounts"] {
            guard let hints = try? JSONDecoder().decode([LegacyAccountHint].self, from: Data(raw.utf8)), hints.count <= 10,
                  Set(hints.map(\.uid)).count == hints.count,
                  hints.allSatisfy({ Self.validText($0.uid, allowEmpty: false) && Self.validText($0.nickname ?? "", allowEmpty: true) }) else { throw LegacyImportError.invalidData }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            sanitized["ylf_saved_accounts"] = String(data: try encoder.encode(hints), encoding: .utf8)
        }
        self.values = sanitized
        if hasHome {
            guard let configuration else { throw LegacyImportError.invalidData }
            do { try configuration.validate() } catch { throw LegacyImportError.invalidData }
        }
        if let appearance, !["system", "light", "dark"].contains(appearance) { throw LegacyImportError.invalidData }
        for key in ["ylf:cloud-sync-enabled", "ylf:cloud-auto-sync", "ylf:dock-visible"] {
            if let value = values[key], !["true", "false"].contains(value) { throw LegacyImportError.invalidData }
        }
        let choices = ["ylf_icon_style": ["original", "liquid-glass", "flat-color", "gradient", "minimal"],
                       "ylf:preview-window-size": ["mini", "medium", "large", "small"],
                       "ylf:in-app-browser-mode": ["titlebar", "system", "immersive"],
                       "ylf:external-link-mode": ["safari-view", "default-browser"],
                       "ylf:session-limit-preference": ["auto", "2", "3", "4", "5", "6", "7"]]
        for (key, options) in choices {
            if let value = values[key], !options.contains(value) { throw LegacyImportError.invalidData }
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(values: container.decode([String: String].self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(values)
    }
    private func boolean(_ key: String) -> Bool? { values[key].map { $0 == "true" } }
    private func decode<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try values[key].map { try JSONDecoder().decode(type, from: Data($0.utf8)) }
    }
    private static func validText(_ text: String, allowEmpty: Bool) -> Bool {
        (allowEmpty || !text.isEmpty) && text.utf16.count <= 256 && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && !text.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

struct LegacyImportArchive: Codable {
    var version = 1
    let record: LegacyLocalData
    var claim: Claim?
    struct Claim: Codable, Equatable {
        let accountID: String?
        var completed = false
    }
}

struct LegacyImportConfirmation: Identifiable {
    let id = UUID()
    let recordID: String
    let accountID: String?
    let accountGeneration: UUID
    let libraryGeneration: UUID
}
