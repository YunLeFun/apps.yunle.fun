package `fun`.yunle.apps.workshop

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.WorkshopLink
import `fun`.yunle.apps.account.AuthorizedAccount
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

internal interface WorkshopServing {
    suspend fun mine(identity: AuthorizedAccount): WorkshopManagement?
    suspend fun joined(identity: AuthorizedAccount): List<PersonalWorkshop>
    suspend fun page(id: String, identity: AuthorizedAccount?): WorkshopPage
    suspend fun create(draft: WorkshopDraft, identity: AuthorizedAccount): PersonalWorkshop
    suspend fun update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount): PersonalWorkshop
    suspend fun join(id: String, identity: AuthorizedAccount): WorkshopJoinResult
    suspend fun leave(id: String, identity: AuthorizedAccount): WorkshopMembership
    suspend fun decide(
        id: String,
        member: WorkshopMembership,
        action: WorkshopDecision,
        identity: AuthorizedAccount,
    ): WorkshopMembership
}

internal class WorkshopService(
    private val origin: String = "https://apps.yunle.fun",
) : WorkshopServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun mine(identity: AuthorizedAccount): WorkshopManagement? {
        val json = request("$baseUrl/api/workshops/mine", identity = identity)
        if (!json.has("management")) throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        if (json.isNull("management")) return null
        val mgmtObj = json.optJSONObject("management") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        return WorkshopManagement.fromJson(mgmtObj).also { it.validate(identity.userID) }
    }

    override suspend fun joined(identity: AuthorizedAccount): List<PersonalWorkshop> {
        val json = request("$baseUrl/api/workshops/joined", identity = identity)
        val arr = json.optJSONArray("items") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        if (arr.length() > 100) throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        val list = (0 until arr.length()).map { i ->
            val obj = arr.optJSONObject(i) ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            PersonalWorkshop.fromJson(obj).also { it.validate() }
        }
        if (list.map { it.id }.toSet().size != list.size) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
        return list
    }

    override suspend fun page(id: String, identity: AuthorizedAccount?): WorkshopPage {
        val normalized = normalizeId(id)
        val json = request("$baseUrl/api/workshops/$normalized", identity = identity)
        return WorkshopPage.fromJson(json, normalized).also { it.validate(normalized, identity) }
    }

    override suspend fun create(draft: WorkshopDraft, identity: AuthorizedAccount): PersonalWorkshop {
        if (!draft.isValid) throw WorkshopException(WorkshopError.INVALID_INPUT)
        val body = JSONObject()
            .put("name", draft.name.trim())
            .put("description", draft.description.trim())
        val json = request("$baseUrl/api/workshops", method = "POST", fields = body, identity = identity)
        val obj = json.optJSONObject("workshop") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        return PersonalWorkshop.fromJson(obj).also {
            it.validate(expectedOwner = identity.userID)
            if (it.joinPolicy != WorkshopJoinPolicy.APPROVAL || it.status != WorkshopStatus.ACTIVE) {
                throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            }
        }
    }

    override suspend fun update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount): PersonalWorkshop {
        if (!draft.isValid) throw WorkshopException(WorkshopError.INVALID_INPUT)
        val normalized = normalizeId(id)
        val body = JSONObject()
            .put("name", draft.name.trim())
            .put("description", draft.description.trim())
            .put("joinPolicy", draft.joinPolicy.key)
            .put("status", draft.status.key)
        val json = request("$baseUrl/api/workshops/$normalized", method = "PATCH", fields = body, identity = identity)
        val obj = json.optJSONObject("workshop") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        return PersonalWorkshop.fromJson(obj).also {
            it.validate(expectedId = normalized, expectedOwner = identity.userID)
            if (it.joinPolicy != draft.joinPolicy || it.status != draft.status) {
                throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            }
        }
    }

    override suspend fun join(id: String, identity: AuthorizedAccount): WorkshopJoinResult {
        val normalized = normalizeId(id)
        val json = request("$baseUrl/api/workshops/$normalized/join", method = "POST", identity = identity)
        return WorkshopJoinResult.fromJson(json).also { it.validate() }
    }

    override suspend fun leave(id: String, identity: AuthorizedAccount): WorkshopMembership {
        val normalized = normalizeId(id)
        val json = request("$baseUrl/api/workshops/$normalized/leave", method = "POST", identity = identity)
        val obj = json.optJSONObject("membership") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        return WorkshopMembership.fromJson(obj).also {
            it.validate(
                expectedWorkshopId = normalized,
                expectedUid = identity.userID,
                expectedStatus = WorkshopMembershipStatus.LEFT,
            )
        }
    }

    override suspend fun decide(
        id: String,
        member: WorkshopMembership,
        action: WorkshopDecision,
        identity: AuthorizedAccount,
    ): WorkshopMembership {
        val normalized = normalizeId(id)
        val uid = member.userUid
        if (member.workshopId != normalized ||
            !action.allows(member.status) ||
            uid.isEmpty() ||
            uid == identity.userID ||
            uid.length > 256 ||
            uid == "." ||
            uid == ".." ||
            uid.any { it.code < 32 || it.code == 127 }
        ) {
            throw WorkshopException(WorkshopError.INVALID_INPUT)
        }
        val segment = URLEncoder.encode(uid, Charsets.UTF_8.name()).replace("+", "%20")
        val body = JSONObject().put("action", action.key)
        val json = request(
            urlString = "$baseUrl/api/workshops/$normalized/members/$segment",
            method = "POST",
            fields = body,
            identity = identity,
        )
        val obj = json.optJSONObject("membership") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        return WorkshopMembership.fromJson(obj).also {
            it.validate(
                expectedWorkshopId = normalized,
                expectedUid = uid,
                expectedStatus = action.resultStatus,
            )
        }
    }

    private fun normalizeId(id: String): String =
        WorkshopLink.normalize(id) ?: throw WorkshopException(WorkshopError.INVALID_INPUT)

    private suspend fun request(
        urlString: String,
        method: String = "GET",
        fields: JSONObject? = null,
        identity: AuthorizedAccount?,
    ): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            if (identity != null) {
                setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            }
            if (fields != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (fields != null) {
                conn.outputStream.use { it.write(fields.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            when (code) {
                400 -> throw WorkshopException(WorkshopError.INVALID_INPUT)
                401 -> throw WorkshopException(WorkshopError.UNAUTHORIZED)
                403 -> throw WorkshopException(WorkshopError.FORBIDDEN)
                404 -> throw WorkshopException(WorkshopError.NOT_FOUND)
                409 -> throw WorkshopException(WorkshopError.CONFLICT)
                429 -> throw WorkshopException(WorkshopError.THROTTLED)
                in 200..299 -> Unit
                else -> throw WorkshopException(WorkshopError.UNAVAILABLE)
            }
            val stream = conn.inputStream
            val buffer = ByteArray(8192)
            val out = ByteArrayOutputStream()
            stream.use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count == -1) break
                    if (out.size() + count > MAXIMUM_BYTES) {
                        throw WorkshopException(WorkshopError.INVALID_RESPONSE)
                    }
                    out.write(buffer, 0, count)
                }
            }
            JSONObject(out.toString(Charsets.UTF_8.name()))
        } catch (e: WorkshopException) {
            throw e
        } catch (t: Throwable) {
            throw WorkshopException(WorkshopError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val MAXIMUM_BYTES = 2 * 1024 * 1024
    }
}

internal object WorkshopLaunchAuthorization {
    suspend fun resolve(
        app: CatalogApp,
        identity: AuthorizedAccount?,
        service: WorkshopServing,
    ): CatalogApp {
        val id = app.accessWorkshopId ?: throw WorkshopException(WorkshopError.FORBIDDEN)
        val page = service.page(id, identity)
        if (!page.permitsApps) throw WorkshopException(WorkshopError.FORBIDDEN)
        val current = page.apps.firstOrNull { it.id == app.id } ?: throw WorkshopException(WorkshopError.FORBIDDEN)
        if (current.launchUrl == null) throw WorkshopException(WorkshopError.FORBIDDEN)
        return current
    }
}
