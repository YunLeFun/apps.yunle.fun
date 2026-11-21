package `fun`.yunle.apps.home

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID

internal enum class HomeBackupKind(val label: String) {
    CONFLICT("选择云端版本前"),
    RESTORE("恢复备份前"),
    LEGACY("导入旧版数据前"),
    NATIVE_MIGRATION("迁移旧版数据前"),
}

internal data class HomeBackupItem(
    val id: String,
    val kind: HomeBackupKind,
    val savedAtMillis: Long,
    val byteCount: Long,
)

internal data class HomeBackupPreview(
    val item: HomeBackupItem,
    val snapshot: HomeLibrarySnapshot,
    val sha256Digest: String,
)

internal enum class HomeBackupError(val message: String) {
    UNREADABLE("这份备份无法读取，可能已损坏。"),
    IDENTITY_CHANGED("账号或云居状态已变化，请重新打开后再试。"),
    BACKUP_CHANGED("备份文件在预览后发生变化，已取消恢复。"),
}

internal class HomeBackupException(
    val error: HomeBackupError,
    cause: Throwable? = null,
) : Exception(error.message, cause)

internal class HomeBackupRepository(private val directory: File) {

    fun list(ownerFileName: String): List<HomeBackupItem> {
        if (!directory.exists() || !directory.isDirectory) return emptyList()
        val files = directory.listFiles() ?: return emptyList()
        return files.mapNotNull { file ->
            val kind = kind(file.name, ownerFileName) ?: return@mapNotNull null
            if (Files.isSymbolicLink(file.toPath()) || !file.isFile) return@mapNotNull null
            val length = file.length()
            if (length > MAXIMUM_BYTES) return@mapNotNull null
            HomeBackupItem(
                id = file.name,
                kind = kind,
                savedAtMillis = file.lastModified().coerceAtLeast(0L),
                byteCount = length,
            )
        }.sortedWith(
            compareByDescending<HomeBackupItem> { it.savedAtMillis }
                .thenByDescending { it.id },
        )
    }

    fun preview(id: String, ownerFileName: String): HomeBackupPreview {
        val kind = kind(id, ownerFileName) ?: throw HomeBackupException(HomeBackupError.UNREADABLE)
        val file = File(directory, id)
        return try {
            val path = file.toPath()
            if (Files.isSymbolicLink(path) || !file.isFile) {
                throw HomeBackupException(HomeBackupError.UNREADABLE)
            }
            val length = file.length()
            if (length > MAXIMUM_BYTES) {
                throw HomeBackupException(HomeBackupError.UNREADABLE)
            }
            val bytes = file.readBytes()
            if (bytes.size > MAXIMUM_BYTES) {
                throw HomeBackupException(HomeBackupError.UNREADABLE)
            }
            val json = JSONObject(String(bytes, Charsets.UTF_8))
            val snapshot = HomeLibrary.parseSnapshotJson(json)
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { "%02x".format(it) }
            HomeBackupPreview(
                item = HomeBackupItem(
                    id = id,
                    kind = kind,
                    savedAtMillis = file.lastModified().coerceAtLeast(0L),
                    byteCount = bytes.size.toLong(),
                ),
                snapshot = snapshot,
                sha256Digest = digest,
            )
        } catch (e: HomeBackupException) {
            throw e
        } catch (t: Throwable) {
            throw HomeBackupException(HomeBackupError.UNREADABLE, t)
        }
    }

    companion object {
        const val MAXIMUM_BYTES = 16 * 1024 * 1024
        private val HEX_64_RE = Regex("^[0-9a-f]{64}$")
        private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

        fun kind(name: String, ownerFileName: String): HomeBackupKind? {
            if (!ownerFileName.endsWith(".json") ||
                ownerFileName.contains('/') ||
                ownerFileName.contains('\\')
            ) {
                return null
            }
            val prefix = "${ownerFileName.removeSuffix(".json")}."
            if (!name.startsWith(prefix) ||
                !name.endsWith(".json") ||
                name.contains('/') ||
                name.contains('\\')
            ) {
                return null
            }
            val suffix = name.removePrefix(prefix).removeSuffix(".json")
            for ((token, kind) in listOf(
                "before-legacy-" to HomeBackupKind.LEGACY,
                "before-native-migration-" to HomeBackupKind.NATIVE_MIGRATION,
            )) {
                if (suffix.startsWith(token)) {
                    val digest = suffix.removePrefix(token)
                    return if (HEX_64_RE.matches(digest)) kind else null
                }
            }
            for ((token, kind) in listOf(
                "conflict-" to HomeBackupKind.CONFLICT,
                "before-restore-" to HomeBackupKind.RESTORE,
            )) {
                if (suffix.startsWith(token)) {
                    val rawUuid = suffix.removePrefix(token)
                    return if (UUID_RE.matches(rawUuid) && runCatching { UUID.fromString(rawUuid) }.isSuccess) {
                        kind
                    } else {
                        null
                    }
                }
            }
            return null
        }
    }
}
