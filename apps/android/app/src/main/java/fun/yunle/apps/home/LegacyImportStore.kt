package `fun`.yunle.apps.home

import `fun`.yunle.apps.AppAppearance
import `fun`.yunle.apps.YunlePreferences
import `fun`.yunle.apps.account.AccountStore
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

internal class LegacyImportStore(
    private val library: HomeLibrary,
    private val accounts: AccountStore,
    private val reader: LegacyLocalDataReading,
    directory: File,
    private val saveAppearance: (AppAppearance) -> Boolean,
) {
    constructor(
        library: HomeLibrary,
        accounts: AccountStore,
        reader: LegacyLocalDataReading,
        directory: File,
        preferences: YunlePreferences,
    ) : this(library, accounts, reader, directory, preferences::persistImportedAppearance)

    private val archiveFile = File(directory, "record-v1.json")
    private val _archive = MutableStateFlow<LegacyImportArchive?>(null)
    val archive = _archive.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()
    private val _isLoaded = MutableStateFlow(false)
    val isLoaded = _isLoaded.asStateFlow()
    private val _error = MutableStateFlow<LegacyImportError?>(null)
    val error = _error.asStateFlow()

    val targetLabel: String
        get() = accounts.user?.let { "当前账号：${it.displayName}" } ?: "本机访客云居"
    val belongsToCurrentTarget: Boolean
        get() = belongsToTarget(archive.value)
    val visibleArchive: LegacyImportArchive?
        get() = archive.value?.takeIf(::belongsToTarget)

    suspend fun load(retry: Boolean = false) {
        synchronized(archiveLock) {
            if (_isLoading.value || (_isLoaded.value && !retry)) return
            _isLoading.value = true
            _isLoaded.value = false
            _error.value = null
        }
        try {
            val stored = withContext(Dispatchers.IO) {
                synchronized(archiveLock) { readStoredArchive() }
            }
            val loaded = if (stored != null) stored else {
                val values = reader.read()
                withContext(Dispatchers.IO) {
                    synchronized(archiveLock) {
                        ensureActive()
                        // A different store may have saved a destination during the read.
                        readStoredArchive() ?: LegacyLocalData(values)
                            .takeIf { it.values.isNotEmpty() }
                            ?.let { LegacyImportArchive(record = it).also(::save) }
                    }
                }
            }
            _archive.value = loaded
            _isLoaded.value = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: LegacyImportException) {
            _error.value = e.error
        } catch (_: Exception) {
            _error.value = LegacyImportError.UNREADABLE
        } finally {
            _isLoading.value = false
        }
    }

    // Confirmation and application run synchronously with account selection on Main.
    fun prepareConfirmation(): LegacyImportConfirmation? = synchronized(archiveLock) {
        val displayed = _archive.value
        if (!_isLoaded.value || _isLoading.value || displayed == null) return null
        try {
            val current = refreshArchive(displayed.record.id)
            if (!belongsToTarget(current)) throw LegacyImportException(LegacyImportError.ALREADY_CLAIMED)
            if (current.claim?.completed == true) return null
            val confirmation = LegacyImportConfirmation(
                recordID = current.record.id,
                accountID = library.activeAccountId,
                accountGeneration = accounts.identityGeneration.value,
                libraryGeneration = library.generation.value,
            )
            checkBoundary(confirmation)
            _error.value = null
            confirmation
        } catch (e: LegacyImportException) {
            _error.value = e.error
            null
        }
    }

    fun apply(confirmation: LegacyImportConfirmation) {
        synchronized(archiveLock) {
            try {
                if (!_isLoaded.value || _isLoading.value || _archive.value == null) {
                    throw LegacyImportException(LegacyImportError.IDENTITY_CHANGED)
                }
                checkBoundary(confirmation)
                val current = refreshArchive(confirmation.recordID)
                if (current.claim != null && current.claim.accountID != confirmation.accountID) {
                    throw LegacyImportException(LegacyImportError.ALREADY_CLAIMED)
                }
                if (current.claim?.completed == true) return

                // Persist the destination before changing Home so failures can only resume there.
                val claim = LegacyImportArchive.Claim(accountID = confirmation.accountID)
                val claimed = current.copy(claim = claim)
                save(claimed)
                _archive.value = claimed

                checkBoundary(confirmation)
                library.importLegacy(current.record, confirmation.accountID, confirmation.libraryGeneration)
                current.record.appearance?.let {
                    if (!saveAppearance(AppAppearance.fromKey(it))) {
                        throw LegacyImportException(LegacyImportError.STORAGE)
                    }
                }

                val completed = claimed.copy(claim = claim.copy(completed = true))
                save(completed)
                _archive.value = completed
                _error.value = null
            } catch (e: LegacyImportException) {
                _error.value = e.error
            } catch (_: Exception) {
                _error.value = LegacyImportError.STORAGE
            }
        }
    }

    fun identityChanged() {
        synchronized(archiveLock) {
            val previous = _error.value
            if (previous == LegacyImportError.ALREADY_CLAIMED || previous == LegacyImportError.IDENTITY_CHANGED) {
                _error.value = null
            }
        }
    }

    private fun belongsToTarget(archive: LegacyImportArchive?): Boolean =
        archive?.claim?.let { it.accountID == library.activeAccountId && it.accountID == accounts.user?.id } ?: true

    private fun checkBoundary(confirmation: LegacyImportConfirmation) {
        val user = accounts.user
        if (confirmation.accountID != library.activeAccountId ||
            confirmation.accountID != user?.id ||
            confirmation.accountGeneration != accounts.identityGeneration.value ||
            confirmation.libraryGeneration != library.generation.value ||
            (user != null && !user.isUsable)
        ) throw LegacyImportException(LegacyImportError.IDENTITY_CHANGED)
    }

    private fun refreshArchive(expectedID: String): LegacyImportArchive {
        val current = try {
            readStoredArchive() ?: throw LegacyImportException(LegacyImportError.RECORD_CHANGED)
        } catch (e: LegacyImportException) {
            _isLoaded.value = false
            throw e
        }
        _archive.value = current
        if (current.record.id != expectedID) {
            _isLoaded.value = false
            throw LegacyImportException(LegacyImportError.RECORD_CHANGED)
        }
        return current
    }

    private fun readStoredArchive(): LegacyImportArchive? {
        val path = archiveFile.toPath()
        try {
            // NOFOLLOW_LINKS also prevents opening a link swapped in after the file check.
            if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                if (Files.notExists(path, LinkOption.NOFOLLOW_LINKS)) return null
                throw LegacyImportException(LegacyImportError.UNREADABLE)
            }
            if (Files.size(path) > MAXIMUM_ARCHIVE_BYTES) throw LegacyImportException(LegacyImportError.INVALID_DATA)
            return Files.newInputStream(path, LinkOption.NOFOLLOW_LINKS).use { input ->
                val bytes = ByteArray(MAXIMUM_ARCHIVE_BYTES + 1)
                var size = 0
                while (size < bytes.size) {
                    val count = input.read(bytes, size, bytes.size - size)
                    if (count < 0) break
                    size += count
                }
                if (size > MAXIMUM_ARCHIVE_BYTES) throw LegacyImportException(LegacyImportError.INVALID_DATA)
                val raw = try {
                    bytes.decodeToString(endIndex = size, throwOnInvalidSequence = true)
                } catch (_: IOException) {
                    throw LegacyImportException(LegacyImportError.INVALID_DATA)
                }
                LegacyImportArchive.fromJson(raw)
            }
        } catch (_: NoSuchFileException) {
            return null
        } catch (e: IOException) {
            throw LegacyImportException(LegacyImportError.UNREADABLE, e)
        } catch (e: SecurityException) {
            throw LegacyImportException(LegacyImportError.UNREADABLE, e)
        }
    }

    private fun save(archive: LegacyImportArchive) {
        try {
            val bytes = archive.toJson().toByteArray()
            if (bytes.size > MAXIMUM_ARCHIVE_BYTES) throw LegacyImportException(LegacyImportError.INVALID_DATA)
            writeLegacyMigrationFile(archiveFile, bytes)
        } catch (e: IOException) {
            throw LegacyImportException(LegacyImportError.STORAGE, e)
        } catch (e: SecurityException) {
            throw LegacyImportException(LegacyImportError.STORAGE, e)
        }
    }

    private companion object {
        const val MAXIMUM_ARCHIVE_BYTES = 1_048_576
        val archiveLock = Any()
    }
}

internal fun writeLegacyMigrationFile(file: File, bytes: ByteArray) {
    val parent = checkNotNull(file.parentFile).toPath()
    Files.createDirectories(parent)
    val temp = Files.createTempFile(parent, file.name, ".tmp")
    try {
        temp.toFile().outputStream().use {
            it.write(bytes)
            it.fd.sync()
        }
        Files.move(temp, file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    } finally {
        Files.deleteIfExists(temp)
    }
}
