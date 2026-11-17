package `fun`.yunle.apps.webruntime

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.CloudbaseAuthService
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

class WebProfileRepository(
    private val file: File,
    private val namespace: String = CloudbaseAuthService.GATEWAY_ORIGIN,
) {
    sealed class Principal {
        data object Guest : Principal()
        data class Account(val id: String) : Principal()
    }

    data class Selection(
        val identifier: UUID,
        internal val owner: String,
        internal val application: String,
    ) {
        internal val key: String
            get() = "$owner/$application"

        val profileName: String
            get() = "ylf_${identifier.toString().replace("-", "")}"
    }

    data class Snapshot(
        val active: Selection?,
        val retained: List<Selection>,
    )

    sealed class ContinuationDisposition {
        data class Adopted(val selection: Selection) : ContinuationDisposition()
        data class Retained(val continuation: Selection, val existing: Selection) : ContinuationDisposition()
    }

    enum class Failure {
        INVALID_IDENTITY,
        INVALID_STATE,
        UNSUPPORTED_VERSION,
        STALE_SELECTION,
    }

    class ProfileException(val failure: Failure, cause: Throwable? = null) : Exception(failure.name, cause)

    private data class State(
        val version: Int = 1,
        val active: MutableMap<String, UUID> = linkedMapOf(),
        val retained: MutableMap<String, MutableList<UUID>> = linkedMapOf(),
    )

    private val lock = Any()

    internal fun select(
        principal: Principal,
        application: CatalogApp,
        runtimeScope: String = "public",
    ): Selection = select(principal, application.id, application.launchUrl, runtimeScope)

    internal fun select(
        principal: Principal,
        applicationID: String,
        launchUrl: String?,
        runtimeScope: String = "public",
    ): Selection = synchronized(lock) {
        val owner = ownerKey(principal)
        val app = applicationKey(applicationID, launchUrl, runtimeScope)
        val key = "$owner/$app"
        updateLocked { state ->
            val existing = state.active[key]
            if (existing != null) {
                Selection(identifier = existing, owner = owner, application = app)
            } else {
                val created = UUID.randomUUID()
                state.active[key] = created
                Selection(identifier = created, owner = owner, application = app)
            }
        }
    }

    fun bindGuestContinuation(selected: Selection, accountID: String): ContinuationDisposition = synchronized(lock) {
        val guest = ownerKey(Principal.Guest)
        val owner = ownerKey(Principal.Account(accountID))
        if (selected.owner != guest) throw ProfileException(Failure.STALE_SELECTION)
        val destination = "$owner/${selected.application}"
        updateLocked { state ->
            if (state.active[selected.key] != selected.identifier) {
                throw ProfileException(Failure.STALE_SELECTION)
            }
            state.active.remove(selected.key)
            val continuation = Selection(
                identifier = selected.identifier,
                owner = owner,
                application = selected.application,
            )
            val existingID = state.active[destination]
            if (existingID != null) {
                state.retained.getOrPut(destination) { mutableListOf() }.add(selected.identifier)
                ContinuationDisposition.Retained(
                    continuation = continuation,
                    existing = Selection(identifier = existingID, owner = owner, application = selected.application),
                )
            } else {
                state.active[destination] = selected.identifier
                ContinuationDisposition.Adopted(continuation)
            }
        }
    }

    fun retire(accountID: String): Unit = synchronized(lock) {
        val prefix = "${ownerKey(Principal.Account(accountID))}/"
        updateLocked { state ->
            val matchingKeys = state.active.keys.filter { it.startsWith(prefix) }
            for (key in matchingKeys) {
                val id = state.active.remove(key) ?: continue
                state.retained.getOrPut(key) { mutableListOf() }.add(id)
            }
        }
    }

    internal fun retained(
        principal: Principal,
        application: CatalogApp,
        runtimeScope: String = "public",
    ): List<Selection> = snapshot(principal, application, runtimeScope).retained

    internal fun snapshot(
        principal: Principal,
        application: CatalogApp,
        runtimeScope: String = "public",
    ): Snapshot = synchronized(lock) {
        val owner = ownerKey(principal)
        val app = applicationKey(application.id, application.launchUrl, runtimeScope)
        val state = readLocked()
        val key = "$owner/$app"
        Snapshot(
            active = state.active[key]?.let { Selection(identifier = it, owner = owner, application = app) },
            retained = state.retained[key].orEmpty().map { Selection(identifier = it, owner = owner, application = app) },
        )
    }

    internal fun activateRetained(
        selected: Selection,
        accountID: String,
        application: CatalogApp,
        replacing: Selection?,
        runtimeScope: String = "public",
    ): Unit = synchronized(lock) {
        val owner = ownerKey(Principal.Account(accountID))
        val app = applicationKey(application.id, application.launchUrl, runtimeScope)
        if (selected.owner != owner || selected.application != app ||
            (replacing != null && (replacing.owner != owner || replacing.application != app))
        ) {
            throw ProfileException(Failure.STALE_SELECTION)
        }
        updateLocked { state ->
            val key = selected.key
            val retainedList = state.retained[key]
            val index = retainedList?.indexOf(selected.identifier) ?: -1
            if (state.active[key] != replacing?.identifier || index < 0) {
                throw ProfileException(Failure.STALE_SELECTION)
            }
            retainedList!!.removeAt(index)
            if (retainedList.isEmpty()) state.retained.remove(key)
            val previous = state.active[key]
            if (previous != null) {
                state.retained.getOrPut(key) { mutableListOf() }.add(previous)
            }
            state.active[key] = selected.identifier
        }
    }

    private fun ownerKey(principal: Principal): String {
        if (namespace.isEmpty()) throw ProfileException(Failure.INVALID_IDENTITY)
        return when (principal) {
            is Principal.Guest -> digest(listOf(namespace, "guest"))
            is Principal.Account -> {
                val id = principal.id
                if (id.isEmpty() || id.trim() != id) throw ProfileException(Failure.INVALID_IDENTITY)
                digest(listOf(namespace, "account", id))
            }
        }
    }

    private fun applicationKey(applicationID: String, launchUrl: String?, runtimeScope: String): String {
        if (launchUrl == null) throw ProfileException(Failure.INVALID_IDENTITY)
        val uri = runCatching { URI(launchUrl) }.getOrNull() ?: throw ProfileException(Failure.INVALID_IDENTITY)
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()
        if (applicationID.isEmpty() || (scheme != "https" && scheme != "http") || host.isNullOrEmpty()) {
            throw ProfileException(Failure.INVALID_IDENTITY)
        }
        val port = if (uri.port != -1) uri.port else if (scheme == "https") 443 else 80
        return digest(listOf(applicationID, runtimeScope, scheme, host, port.toString()))
    }

    private fun digest(parts: List<String>): String {
        val jsonArray = JSONArray(parts).toString().toByteArray(Charsets.UTF_8)
        val bytes = MessageDigest.getInstance("SHA-256").digest(jsonArray)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun readLocked(): State {
        if (!file.exists()) return State()
        val raw = runCatching { file.readText(Charsets.UTF_8) }.getOrElse {
            throw ProfileException(Failure.INVALID_STATE, it)
        }
        val json = runCatching { JSONObject(raw) }.getOrElse {
            throw ProfileException(Failure.INVALID_STATE, it)
        }
        val version = json.optInt("version", -1)
        if (version != 1) throw ProfileException(Failure.UNSUPPORTED_VERSION)
        val activeMap = linkedMapOf<String, UUID>()
        val activeJson = json.optJSONObject("active") ?: throw ProfileException(Failure.INVALID_STATE)
        for (key in activeJson.keys()) {
            val uuid = runCatching { UUID.fromString(activeJson.getString(key)) }.getOrElse {
                throw ProfileException(Failure.INVALID_STATE, it)
            }
            activeMap[key] = uuid
        }
        val retainedMap = linkedMapOf<String, MutableList<UUID>>()
        val retainedJson = json.optJSONObject("retained") ?: throw ProfileException(Failure.INVALID_STATE)
        for (key in retainedJson.keys()) {
            val arr = retainedJson.optJSONArray(key) ?: throw ProfileException(Failure.INVALID_STATE)
            val list = mutableListOf<UUID>()
            for (i in 0 until arr.length()) {
                val uuid = runCatching { UUID.fromString(arr.getString(i)) }.getOrElse {
                    throw ProfileException(Failure.INVALID_STATE, it)
                }
                list.add(uuid)
            }
            if (list.isNotEmpty()) retainedMap[key] = list
        }
        val state = State(version = version, active = activeMap, retained = retainedMap)
        validate(state)
        return state
    }

    private fun <T> updateLocked(block: (State) -> T): T {
        val state = readLocked()
        val beforeActive = state.active.toMap()
        val beforeRetained = state.retained.mapValues { it.value.toList() }
        val result = block(state)
        validate(state)
        if (state.active != beforeActive || state.retained != beforeRetained) {
            val serialized = JSONObject().apply {
                put("version", state.version)
                put("active", JSONObject().apply {
                    state.active.toSortedMap().forEach { (k, v) -> put(k, v.toString()) }
                })
                put("retained", JSONObject().apply {
                    state.retained.toSortedMap().forEach { (k, list) ->
                        put(k, JSONArray(list.map { it.toString() }))
                    }
                })
            }.toString()
            val destination = file.absoluteFile.toPath()
            val directory = Files.createDirectories(destination.parent)
            val temp = Files.createTempFile(directory, "ownership-", ".tmp")
            try {
                temp.toFile().outputStream().use { stream ->
                    stream.write(serialized.toByteArray(Charsets.UTF_8))
                    stream.fd.sync()
                }
                Files.move(temp, destination, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } finally {
                Files.deleteIfExists(temp)
            }
        }
        return result
    }

    private fun validate(state: State) {
        val allKeys = state.active.keys + state.retained.keys
        val validKeyFormat = allKeys.all { key ->
            val parts = key.split("/")
            parts.size == 2 && parts.all { part ->
                part.length == 64 && part.all { ch -> ch in '0'..'9' || ch in 'a'..'f' }
            }
        }
        val allIds = state.active.values + state.retained.values.flatten()
        if (!validKeyFormat || allIds.distinct().size != allIds.size) {
            throw ProfileException(Failure.INVALID_STATE)
        }
    }
}
