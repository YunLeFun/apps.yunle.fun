package `fun`.yunle.apps.workshop

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.WorkshopLink
import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.readString
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.floor

internal enum class WorkshopError(val defaultMessage: String) {
    INVALID_INPUT("请检查工坊编号、名称和内容长度。"),
    INVALID_RESPONSE("工坊返回的信息无法读取，请刷新后重试。"),
    UNAUTHORIZED("登录状态已失效，请重新登录。"),
    FORBIDDEN("当前账号没有此权限，请刷新工坊状态。"),
    NOT_FOUND("这个工坊已不存在或暂不可访问。"),
    CONFLICT("工坊或坊客状态已变化，请刷新后再试。"),
    THROTTLED("操作较频繁，请稍后再试。"),
    UNAVAILABLE("暂时无法连接工坊，请检查网络后重试。"),
    IDENTITY_CHANGED("账号已变化，请重新打开此页面。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun message(error: Throwable): String = when (error) {
            is WorkshopException -> error.error.defaultMessage
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class WorkshopException(
    val error: WorkshopError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal enum class WorkshopJoinPolicy(val key: String, val label: String) {
    APPROVAL("approval", "需要审批"),
    OPEN("open", "自由加入"),
    CLOSED("closed", "停止加入");

    companion object {
        fun fromKey(raw: String?): WorkshopJoinPolicy =
            entries.firstOrNull { it.key == raw }
                ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
    }
}

internal enum class WorkshopStatus(val key: String, val label: String) {
    ACTIVE("active", "开放中"),
    DISABLED("disabled", "已暂停");

    companion object {
        fun fromKey(raw: String?): WorkshopStatus =
            entries.firstOrNull { it.key == raw }
                ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
    }
}

internal enum class WorkshopAccess(val key: String) {
    ANONYMOUS("anonymous"),
    NONE("none"),
    PENDING("pending"),
    ACTIVE("active"),
    OWNER("owner"),
    BLOCKED("blocked");

    companion object {
        fun fromKey(raw: String?): WorkshopAccess =
            entries.firstOrNull { it.key == raw }
                ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
    }
}

internal enum class WorkshopMembershipStatus(val key: String) {
    PENDING("pending"),
    ACTIVE("active"),
    REJECTED("rejected"),
    LEFT("left"),
    REMOVED("removed"),
    BLOCKED("blocked");

    companion object {
        fun fromKey(raw: String?): WorkshopMembershipStatus =
            entries.firstOrNull { it.key == raw }
                ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
    }
}

internal enum class WorkshopDecision(
    val key: String,
    val label: String,
    val resultStatus: WorkshopMembershipStatus,
) {
    APPROVE("approve", "通过申请", WorkshopMembershipStatus.ACTIVE),
    REJECT("reject", "拒绝申请", WorkshopMembershipStatus.REJECTED),
    REMOVE("remove", "移出工坊", WorkshopMembershipStatus.REMOVED),
    BLOCK("block", "禁止加入", WorkshopMembershipStatus.BLOCKED),
    UNBLOCK("unblock", "解除禁止", WorkshopMembershipStatus.REMOVED);

    fun allows(status: WorkshopMembershipStatus): Boolean = when (this) {
        APPROVE, REJECT -> status == WorkshopMembershipStatus.PENDING
        REMOVE -> status == WorkshopMembershipStatus.ACTIVE
        BLOCK -> status == WorkshopMembershipStatus.ACTIVE || status == WorkshopMembershipStatus.PENDING
        UNBLOCK -> status == WorkshopMembershipStatus.BLOCKED
    }
}

internal data class PersonalWorkshop(
    val id: String,
    val ownerName: String,
    val ownerAvatar: String?,
    val name: String,
    val description: String?,
    val joinPolicy: WorkshopJoinPolicy,
    val status: WorkshopStatus,
    val ownerUid: String?,
) {
    val shareUrl: String get() = "https://apps.yunle.fun/w/$id"

    fun validate(expectedId: String? = null, expectedOwner: String? = null) {
        val descBytes = description?.toByteArray(Charsets.UTF_16BE)?.size?.div(2) ?: 0
        val nameUtf16 = name.length
        if (WorkshopLink.normalize(id) != id ||
            (expectedId != null && id != expectedId) ||
            name.trim().isEmpty() ||
            nameUtf16 > 200 ||
            descBytes > 200 ||
            (expectedOwner != null && ownerUid != expectedOwner)
        ) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): PersonalWorkshop = PersonalWorkshop(
            id = json.readString("_id") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            ownerName = json.readString("ownerName").orEmpty(),
            ownerAvatar = json.readString("ownerAvatar")?.takeIf(String::isNotBlank),
            name = json.readString("name") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            description = json.readString("description"),
            joinPolicy = WorkshopJoinPolicy.fromKey(json.readString("joinPolicy")),
            status = WorkshopStatus.fromKey(json.readString("status")),
            ownerUid = json.readString("ownerUid"),
        )
    }
}

internal data class WorkshopMembership(
    val workshopId: String,
    val userUid: String,
    val userName: String?,
    val userAvatar: String?,
    val status: WorkshopMembershipStatus,
    val requestedAt: Long?,
    val joinedAt: Long?,
    val updatedAt: Long,
) {
    val id: String get() = userUid
    val displayName: String get() = userName?.trim()?.takeIf(String::isNotEmpty) ?: "坊客"

    fun validate(
        expectedWorkshopId: String,
        expectedUid: String? = null,
        expectedStatus: WorkshopMembershipStatus? = null,
    ) {
        if (workshopId != expectedWorkshopId ||
            userUid.isEmpty() ||
            userUid.length > 256 ||
            (expectedUid != null && userUid != expectedUid) ||
            (expectedStatus != null && status != expectedStatus) ||
            !isValidTimestamp(updatedAt) ||
            (requestedAt != null && !isValidTimestamp(requestedAt)) ||
            (joinedAt != null && !isValidTimestamp(joinedAt))
        ) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
    }

    companion object {
        private const val MAX_TIMESTAMP = 253_402_300_799_999L

        private fun isValidTimestamp(value: Long): Boolean = value in 1..MAX_TIMESTAMP

        private fun readOptionalTimestamp(json: JSONObject, key: String): Long? {
            if (!json.has(key) || json.isNull(key)) return null
            val raw = json.opt(key)
            if (raw is Boolean || raw !is Number) throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            val d = raw.toDouble()
            if (!d.isFinite() || floor(d) != d) throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            return d.toLong()
        }

        private fun readRequiredTimestamp(json: JSONObject, key: String): Long =
            readOptionalTimestamp(json, key) ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)

        fun fromJson(json: JSONObject): WorkshopMembership = WorkshopMembership(
            workshopId = json.readString("workshopId") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            userUid = json.readString("userUid") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            userName = json.readString("userName"),
            userAvatar = json.readString("userAvatar"),
            status = WorkshopMembershipStatus.fromKey(json.readString("status")),
            requestedAt = readOptionalTimestamp(json, "requestedAt"),
            joinedAt = readOptionalTimestamp(json, "joinedAt"),
            updatedAt = readRequiredTimestamp(json, "updatedAt"),
        )
    }
}

internal data class WorkshopManagement(
    val workshop: PersonalWorkshop,
    val pending: List<WorkshopMembership>,
    val guests: List<WorkshopMembership>,
    val blocked: List<WorkshopMembership>,
) {
    fun validate(ownerUid: String) {
        workshop.validate(expectedOwner = ownerUid)
        val all = pending + guests + blocked
        if (all.map { it.userUid }.toSet().size != all.size || all.any { it.userUid == ownerUid }) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
        pending.forEach { it.validate(workshop.id, expectedStatus = WorkshopMembershipStatus.PENDING) }
        guests.forEach { it.validate(workshop.id, expectedStatus = WorkshopMembershipStatus.ACTIVE) }
        blocked.forEach { it.validate(workshop.id, expectedStatus = WorkshopMembershipStatus.BLOCKED) }
    }

    fun applying(member: WorkshopMembership): WorkshopManagement {
        val nextPending = pending.filterNot { it.userUid == member.userUid }.toMutableList()
        val nextGuests = guests.filterNot { it.userUid == member.userUid }.toMutableList()
        val nextBlocked = blocked.filterNot { it.userUid == member.userUid }.toMutableList()
        when (member.status) {
            WorkshopMembershipStatus.PENDING -> nextPending.add(member)
            WorkshopMembershipStatus.ACTIVE -> nextGuests.add(member)
            WorkshopMembershipStatus.BLOCKED -> nextBlocked.add(member)
            else -> Unit
        }
        return copy(pending = nextPending, guests = nextGuests, blocked = nextBlocked)
    }

    companion object {
        fun fromJson(json: JSONObject): WorkshopManagement = WorkshopManagement(
            workshop = PersonalWorkshop.fromJson(
                json.optJSONObject("workshop") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            ),
            pending = readMembershipArray(json.optJSONArray("pending")),
            guests = readMembershipArray(json.optJSONArray("guests")),
            blocked = readMembershipArray(json.optJSONArray("blocked")),
        )

        private fun readMembershipArray(arr: JSONArray?): List<WorkshopMembership> {
            val array = arr ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            return (0 until array.length()).map { i ->
                val obj = array.optJSONObject(i) ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
                WorkshopMembership.fromJson(obj)
            }
        }
    }
}

internal data class WorkshopPage(
    val surface: String,
    val access: WorkshopAccess,
    val workshop: PersonalWorkshop,
    val apps: List<CatalogApp>,
) {
    val permitsApps: Boolean
        get() = workshop.status == WorkshopStatus.ACTIVE &&
            (access == WorkshopAccess.OWNER || access == WorkshopAccess.ACTIVE)

    fun validate(expectedId: String, identity: AuthorizedAccount?) {
        workshop.validate(expectedId = expectedId)
        val hasIdentity = identity != null
        val accessMatchesIdentity = (hasIdentity && access != WorkshopAccess.ANONYMOUS) ||
            (!hasIdentity && access == WorkshopAccess.ANONYMOUS)
        if (surface != "workshop" ||
            !accessMatchesIdentity ||
            (!permitsApps && apps.isNotEmpty()) ||
            apps.map { it.id }.toSet().size != apps.size ||
            apps.any { it.id.isEmpty() || it.name.isEmpty() || (it.audience != "public" && it.audience != "workshop") }
        ) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject, workshopId: String): WorkshopPage {
            val surface = json.readString("surface") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            val access = WorkshopAccess.fromKey(json.readString("access"))
            val workshop = PersonalWorkshop.fromJson(
                json.optJSONObject("workshop") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
            )
            val permitsApps = workshop.status == WorkshopStatus.ACTIVE &&
                (access == WorkshopAccess.OWNER || access == WorkshopAccess.ACTIVE)
            val appsArr = json.optJSONArray("apps") ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            val apps = (0 until appsArr.length()).map { index ->
                val obj = appsArr.optJSONObject(index) ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
                CatalogApp.readScoped(
                    record = obj,
                    allowWorkshopAudience = true,
                    workshopId = workshopId,
                    allowAuthorizedLaunch = permitsApps,
                ) ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE)
            }
            return WorkshopPage(surface = surface, access = access, workshop = workshop, apps = apps)
        }
    }
}

internal data class WorkshopJoinResult(
    val status: WorkshopMembershipStatus,
    val joined: Boolean,
) {
    fun validate() {
        val validStatus = status == WorkshopMembershipStatus.ACTIVE || status == WorkshopMembershipStatus.PENDING
        if (!validStatus || joined != (status == WorkshopMembershipStatus.ACTIVE)) {
            throw WorkshopException(WorkshopError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): WorkshopJoinResult = WorkshopJoinResult(
            status = WorkshopMembershipStatus.fromKey(json.readString("status")),
            joined = json.opt("joined") as? Boolean ?: throw WorkshopException(WorkshopError.INVALID_RESPONSE),
        )
    }
}

internal data class WorkshopDraft(
    val name: String = "",
    val description: String = "",
    val joinPolicy: WorkshopJoinPolicy = WorkshopJoinPolicy.APPROVAL,
    val status: WorkshopStatus = WorkshopStatus.ACTIVE,
) {
    val isValid: Boolean
        get() = name.trim().isNotEmpty() && name.length <= 40 && description.length <= 200

    companion object {
        fun fromWorkshop(workshop: PersonalWorkshop): WorkshopDraft = WorkshopDraft(
            name = workshop.name,
            description = workshop.description.orEmpty(),
            joinPolicy = workshop.joinPolicy,
            status = workshop.status,
        )
    }
}
