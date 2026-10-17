import Foundation

enum HomeBackupError: LocalizedError {
    case unreadable, storage, identityChanged, currentChanged, backupChanged
    var errorDescription: String? {
        switch self {
        case .unreadable: return "暂时无法读取这份备份，原文件已保留。"
        case .storage: return "未能保存恢复前的版本或恢复云居，请检查设备存储空间后重试。"
        case .identityChanged: return "当前账号或云居已变化，请重新打开备份。"
        case .currentChanged: return "当前云居已有新的更改，请重新查看并确认恢复。"
        case .backupChanged: return "这份备份已变化，请重新打开并确认内容。"
        }
    }
}

struct HomeBackupItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case legacy, conflict, restore, nativeMigration
        var label: String {
            switch self {
            case .legacy: return "旧版导入前"
            case .conflict: return "选择云端版本前"
            case .restore: return "恢复其他备份前"
            case .nativeMigration: return "原生云居升级前"
            }
        }
    }
    let id: String
    let kind: Kind
    let date: Date?
    let byteCount: Int64
}

struct HomeBackupPreview {
    let item: HomeBackupItem
    let snapshot: HomeLibrarySnapshot
    let digest: String
}

struct HomeRestoreBaseline: Equatable {
    let configuration: HomeConfiguration
    let mutationID: String
    let syncEnabled: Bool
    let autoSyncEnabled: Bool
    let dockVisible: Bool
    let legacyImportID: String?
    let lastRestoreID: String?
    let needsRecovery: Bool
    init(_ snapshot: HomeLibrarySnapshot, needsRecovery: Bool) {
        configuration = snapshot.configuration; mutationID = snapshot.mutationId
        syncEnabled = snapshot.syncEnabled; autoSyncEnabled = snapshot.autoSyncEnabled; dockVisible = snapshot.dockVisible
        legacyImportID = snapshot.legacyImportID; lastRestoreID = snapshot.lastRestoreID; self.needsRecovery = needsRecovery
    }
    func matches(_ snapshot: HomeLibrarySnapshot, includingSettings: Bool) -> Bool {
        configuration == snapshot.configuration && mutationID == snapshot.mutationId
            && legacyImportID == snapshot.legacyImportID && lastRestoreID == snapshot.lastRestoreID
            && (!includingSettings || (syncEnabled == snapshot.syncEnabled && autoSyncEnabled == snapshot.autoSyncEnabled && dockVisible == snapshot.dockVisible))
    }
    func matchesDiskContent(_ snapshot: HomeLibrarySnapshot) -> Bool {
        configuration == snapshot.configuration && syncEnabled == snapshot.syncEnabled
            && autoSyncEnabled == snapshot.autoSyncEnabled && dockVisible == snapshot.dockVisible
            && legacyImportID == snapshot.legacyImportID && lastRestoreID == snapshot.lastRestoreID
    }
}

struct HomeBackupBoundary: Equatable {
    let accountID: String?
    let accountGeneration: UUID
    let libraryGeneration: UUID
    let ownerFileName: String
}

struct HomeBackupRestoreConfirmation: Identifiable {
    let id = UUID()
    let backupID: String
    let backupDigest: String
    let boundary: HomeBackupBoundary
    let baseline: HomeRestoreBaseline
    let restoreSettings: Bool
}
