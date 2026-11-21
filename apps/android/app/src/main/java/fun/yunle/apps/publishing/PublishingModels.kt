package `fun`.yunle.apps.publishing

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.community.CommunityValidation
import `fun`.yunle.apps.readString
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.Locale
import kotlin.math.floor

internal enum class PublishingError(val defaultMessage: String) {
    INVALID_INPUT("请检查名称、标识、网址与内容长度。"),
    INVALID_RESPONSE("服务返回的作品信息不完整，请刷新后核对。"),
    UNAUTHORIZED("登录状态已失效，请重新登录。"),
    FORBIDDEN("请使用已验证手机号且状态正常的作品所有者账号操作。"),
    MEMBERSHIP_REQUIRED("AI 制作网页需要有效的云乐坊会员。"),
    NOT_FOUND("作品已不存在或当前账号无权管理。"),
    CONFLICT("作品、市场短名或审核状态已变化，请刷新后核对。"),
    THROTTLED("操作较频繁，请稍后重试。作品保存还有每日次数限制。"),
    UNAVAILABLE("暂时无法连接作品服务，请检查网络后重试。"),
    IDENTITY_CHANGED("账号已变化，请重新打开作品。"),
    STORAGE("无法保存本机草稿，原有文件已保留。"),
    UNSUPPORTED_SERVER("服务暂未支持安全保存。请稍后刷新重试，本机草稿可以继续保留。"),
    CONTENT_REJECTED("网页未通过发布审核，请调整内容后再试。"),
    WEB_BUILD_ROOM_FULL("项目已满，最多 8 人。"),
    WEB_BUILD_INVITE_NOT_MUTUAL("互相关注后才能邀请或加入项目。"),
    WEB_BUILD_INVITE_PEER_UNAVAILABLE("对方当前无法参与项目协作。"),
    WEB_BUILD_ALREADY_JOINED("对方已加入这个项目。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun message(error: Throwable): String = when (error) {
            is PublishingException -> error.error.defaultMessage
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class PublishingException(
    val error: PublishingError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal enum class ApplicationAudience(val key: String, val label: String) {
    PUBLIC("public", "公开作品"),
    WORKSHOP("workshop", "工坊坊客"),
    OWNER("owner", "仅本人");

    companion object {
        fun fromKey(raw: String?): ApplicationAudience? = entries.firstOrNull { it.key == raw }
    }
}

internal enum class ApplicationAccessMode(val key: String, val label: String) {
    PUBLIC("public", "直接访问"),
    LOGIN_REQUIRED("login_required", "需要登录"),
    INVITE_ONLY("invite_only", "需要邀请");

    companion object {
        fun fromKey(raw: String?): ApplicationAccessMode =
            entries.firstOrNull { it.key == raw } ?: PUBLIC
    }
}

internal enum class ApplicationReleaseStage(val key: String, val label: String) {
    STABLE("stable", "正式版"),
    BETA("beta", "测试版");

    companion object {
        fun fromKey(raw: String?): ApplicationReleaseStage =
            entries.firstOrNull { it.key == raw } ?: STABLE
    }
}

internal enum class ApplicationReviewStatus(val key: String) {
    DRAFT("draft"),
    PENDING("pending"),
    IN_REVIEW("in_review"),
    CHANGES_REQUESTED("changes_requested"),
    APPROVED("approved"),
    REJECTED("rejected"),
    WITHDRAWN("withdrawn");

    companion object {
        fun fromKey(raw: String?): ApplicationReviewStatus =
            entries.firstOrNull { it.key == raw }
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
    }
}

internal enum class ApplicationPublicationStatus(val key: String, val label: String) {
    UNPUBLISHED("unpublished", "尚未发布"),
    PUBLISHED("published", "当前版本已发布"),
    SUSPENDED("suspended", "作品已暂停"),
    DELISTED("delisted", "作品已下架");

    companion object {
        fun fromKey(raw: String?): ApplicationPublicationStatus? =
            entries.firstOrNull { it.key == raw }
    }
}

internal enum class ApplicationIconRole(val key: String) {
    APP_ICON("app-icon"),
    MARK("mark");
}

internal object PublishingValue {
    private val WRITE_VERSION_RE = Regex("^[a-f0-9]{64}$")
    private val SLUG_RE = Regex("^[a-z][a-z0-9-]{1,49}$")
    private val HEX_COLOR_RE = Regex("^#[A-Fa-f0-9]{6}$")
    private val GITHUB_REPO_RE = Regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
    private val CLOUD_ICON_PATH_RE = Regex("^/app-icons/[a-fA-F0-9]{16}/[a-fA-F0-9-]{36}\\.png$")

    fun writeVersion(value: String): Boolean =
        value.toByteArray(Charsets.UTF_8).size == 64 && WRITE_VERSION_RE.matches(value)

    fun identifier(value: String): Boolean =
        CommunityValidation.isValidIdentifier(value)

    fun slug(value: String): Boolean = SLUG_RE.matches(value)

    fun hexColor(value: String): Boolean = HEX_COLOR_RE.matches(value)

    fun githubRepo(value: String): Boolean = GITHUB_REPO_RE.matches(value)

    fun https(raw: String): Boolean {
        val value = raw.trim()
        if (value.length > 2048 || value.contains('\n') || value.contains('\r')) return false
        val uri = runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme?.equals("https", ignoreCase = true) == true &&
            !uri.host.isNullOrEmpty() &&
            uri.rawUserInfo == null
    }

    fun host(raw: String): Boolean {
        val value = raw.trim()
        return value.isNotEmpty() &&
            value.length <= 253 &&
            !value.contains('/') &&
            !value.contains(':') &&
            !value.any { it.isWhitespace() }
    }

    fun iconSource(raw: String): Boolean {
        val value = raw.trim()
        if (https(value)) return true
        if (value.length > 2048) return false
        val uri = runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme == "cloud" &&
            !uri.host.isNullOrEmpty() &&
            uri.rawUserInfo == null &&
            uri.rawQuery == null &&
            uri.rawFragment == null &&
            CLOUD_ICON_PATH_RE.matches(uri.rawPath.orEmpty())
    }
}

internal data class ApplicationDraft(
    val name: String = "",
    val slug: String = "",
    val description: String = "",
    val githubRepo: String = "",
    val websiteUrl: String = "",
    val privacyPolicyUrl: String = "",
    val supportUrl: String = "",
    val trustedHosts: List<String> = emptyList(),
    val backupUrl: String = "",
    val logo: String = "",
    val emoji: String = "📱",
    val themeColor: String = "#007AFF",
    val category: String = "其他",
    val appIconSrc: String = "",
    val appIconDarkSrc: String = "",
    val markSrc: String = "",
    val markDarkSrc: String = "",
    val tags: List<String> = emptyList(),
    val audience: ApplicationAudience = ApplicationAudience.PUBLIC,
    val accessMode: ApplicationAccessMode = ApplicationAccessMode.PUBLIC,
    val releaseStage: ApplicationReleaseStage = ApplicationReleaseStage.STABLE,
) {
    val validationIssue: String?
        get() {
            val n = name.trim()
            val s = slug.trim()
            val d = description.trim()
            if (n.isEmpty() || n.length > 50) return "应用名称必填，最多 50 字。"
            if (!PublishingValue.slug(s)) return "应用标识须为 2–50 个小写字母、数字或连字符，并以字母开头。"
            if (d.length > 300) return "简介最多 300 字。"
            val urls = listOf("应用网址" to websiteUrl, "隐私政策" to privacyPolicyUrl, "支持链接" to supportUrl)
            for ((label, v) in urls) {
                if (!PublishingValue.https(v)) return "${label}须为不含账号密码的 HTTPS 网址。"
            }
            if (audience == ApplicationAudience.PUBLIC) {
                val host = runCatching { URI(websiteUrl.trim()).host?.lowercase(Locale.ROOT)?.trimEnd('.') }.getOrNull()
                if (host != "yunle.fun" && !(host?.endsWith(".yunle.fun") == true)) {
                    return "公开作品的应用网址需属于 yunle.fun；外部站点可用于仅本人或工坊可见的作品。"
                }
            }
            if (backupUrl.trim().isNotEmpty() && !PublishingValue.https(backupUrl)) {
                return "备用链接须为 HTTPS 网址。"
            }
            if (githubRepo.trim().isNotEmpty() && !PublishingValue.githubRepo(githubRepo.trim())) {
                return "GitHub 仓库格式为 owner/repo。"
            }
            if (!PublishingValue.hexColor(themeColor.trim())) {
                return "主题色格式为 #RRGGBB。"
            }
            if (emoji.trim().length > 16 || category.trim().length > 40) {
                return "图标文字或分类过长。"
            }
            val actualTags = tags.map { it.trim() }.filter { it.isNotEmpty() }
            val actualHosts = trustedHosts.map { it.trim() }.filter { it.isNotEmpty() }
            if (actualTags.size > 10 || actualTags.any { it.length > 24 }) {
                return "标签最多 10 个，每个最多 24 字。"
            }
            if (actualHosts.size > 10 || actualHosts.any { !PublishingValue.host(it) }) {
                return "授信域名最多 10 个，请仅输入域名。"
            }
            val iconSources = listOf(logo, appIconSrc, appIconDarkSrc, markSrc, markDarkSrc)
            if (iconSources.any { it.trim().isNotEmpty() && !PublishingValue.iconSource(it) }) {
                return "图标须为 HTTPS 图片地址或上传生成的云图标标识。"
            }
            if (appIconSrc.trim().isEmpty() && appIconDarkSrc.trim().isNotEmpty()) {
                return "请先设置默认完整图标。"
            }
            if (markSrc.trim().isEmpty() && markDarkSrc.trim().isNotEmpty()) {
                return "请先设置默认主体图标。"
            }
            return null
        }

    val isValid: Boolean get() = validationIssue == null

    fun toSubmissionJson(): JSONObject {
        val obj = JSONObject()
            .put("name", name.trim())
            .put("slug", slug.trim())
            .put("description", description.trim())
            .put("githubRepo", githubRepo.trim())
            .put("websiteUrl", websiteUrl.trim())
            .put("privacyPolicyUrl", privacyPolicyUrl.trim())
            .put("supportUrl", supportUrl.trim())
            .put("trustedHosts", JSONArray(trustedHosts.map { it.trim() }.filter { it.isNotEmpty() }))
            .put("backupUrl", backupUrl.trim())
            .put("logo", logo.trim())
            .put("emoji", emoji.trim())
            .put("themeColor", themeColor.trim())
            .put("category", category.trim())
            .put("tags", JSONArray(tags.map { it.trim() }.filter { it.isNotEmpty() }))
            .put("audience", audience.key)
            .put("accessMode", accessMode.key)
            .put("releaseStage", releaseStage.key)
            .put("isPublic", audience == ApplicationAudience.PUBLIC)
            .put("kind", "first_party")

        val assets = JSONObject()
        if (appIconSrc.trim().isNotEmpty()) {
            val v = JSONObject().put("src", appIconSrc.trim())
            if (appIconDarkSrc.trim().isNotEmpty()) v.put("darkSrc", appIconDarkSrc.trim())
            assets.put("appIcon", v)
        }
        if (markSrc.trim().isNotEmpty()) {
            val v = JSONObject().put("src", markSrc.trim())
            if (markDarkSrc.trim().isNotEmpty()) v.put("darkSrc", markDarkSrc.trim())
            assets.put("mark", v)
        }
        if (assets.length() > 0) obj.put("iconAssets", assets)
        return obj
    }

    fun toLocalJson(): JSONObject = toSubmissionJson().apply {
        put("kind", JSONObject.NULL)
    }

    companion object {
        fun fromJson(json: JSONObject): ApplicationDraft {
            val rawAudience = ApplicationAudience.fromKey(json.readString("audience"))
                ?: if (json.opt("isPublic") == true) ApplicationAudience.PUBLIC else ApplicationAudience.OWNER
            val hostsArr = json.optJSONArray("trustedHosts")
            val parsedHosts = if (hostsArr == null) {
                emptyList()
            } else {
                (0 until hostsArr.length()).mapNotNull { hostsArr.optString(it).takeIf(String::isNotBlank) }
            }
            val tagsArr = json.optJSONArray("tags")
            val parsedTags = if (tagsArr == null) {
                emptyList()
            } else {
                (0 until tagsArr.length()).mapNotNull { tagsArr.optString(it).takeIf(String::isNotBlank) }
            }
            val iconAssets = json.optJSONObject("iconAssets")
            val appIcon = iconAssets?.optJSONObject("appIcon")
            val mark = iconAssets?.optJSONObject("mark")
            return ApplicationDraft(
                name = json.optString("name", ""),
                slug = json.optString("slug", ""),
                description = json.optString("description", ""),
                githubRepo = json.optString("githubRepo", ""),
                websiteUrl = json.optString("websiteUrl", ""),
                privacyPolicyUrl = json.optString("privacyPolicyUrl", ""),
                supportUrl = json.optString("supportUrl", ""),
                trustedHosts = parsedHosts,
                backupUrl = json.optString("backupUrl", ""),
                logo = json.optString("logo", ""),
                emoji = json.readString("emoji") ?: "📱",
                themeColor = json.readString("themeColor") ?: "#007AFF",
                category = json.readString("category") ?: "其他",
                appIconSrc = appIcon?.readString("src").orEmpty(),
                appIconDarkSrc = appIcon?.readString("darkSrc").orEmpty(),
                markSrc = mark?.readString("src").orEmpty(),
                markDarkSrc = mark?.readString("darkSrc").orEmpty(),
                tags = parsedTags,
                audience = rawAudience,
                accessMode = ApplicationAccessMode.fromKey(json.readString("accessMode")),
                releaseStage = ApplicationReleaseStage.fromKey(json.readString("releaseStage")),
            )
        }
    }
}

internal data class PublishingAccess(
    val writePreconditionVersion: Int?,
    val canSubmitFirstParty: Boolean,
    val thirdPartyEnabled: Boolean,
    val thirdPartyMessage: String,
) {
    companion object {
        fun fromJson(json: JSONObject): PublishingAccess = PublishingAccess(
            writePreconditionVersion = if (json.has("writePreconditionVersion") && !json.isNull("writePreconditionVersion")) {
                json.optInt("writePreconditionVersion", -1).takeIf { it >= 0 }
            } else {
                null
            },
            canSubmitFirstParty = json.opt("canSubmitFirstParty") as? Boolean
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE),
            thirdPartyEnabled = json.opt("thirdPartyEnabled") as? Boolean ?: false,
            thirdPartyMessage = json.optString("thirdPartyMessage", ""),
        )
    }
}

internal data class ApplicationSubmission(
    val id: String,
    val appId: String,
    val submitterUid: String,
    val revision: Int,
    val reviewStatus: ApplicationReviewStatus,
    val snapshot: ApplicationDraft,
    val reviewNote: String?,
) {
    companion object {
        fun fromJson(json: JSONObject): ApplicationSubmission {
            val id = json.readString("_id") ?: json.readString("id")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            val appId = json.readString("appId")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            val submitterUid = json.readString("submitterUid")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            val revision = json.optInt("revision", -1)
            val reviewStatus = ApplicationReviewStatus.fromKey(json.readString("reviewStatus"))
            val snapObj = json.optJSONObject("snapshot")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            return ApplicationSubmission(
                id = id,
                appId = appId,
                submitterUid = submitterUid,
                revision = revision,
                reviewStatus = reviewStatus,
                snapshot = ApplicationDraft.fromJson(snapObj),
                reviewNote = json.readString("reviewNote"),
            )
        }
    }
}

internal data class ApplicationListing(
    val appId: String,
    val shortName: String?,
    val status: String,
    val approvedRevisionId: String?,
    val activeSubmissionId: String?,
    val reason: String?,
) {
    companion object {
        fun fromJson(json: JSONObject): ApplicationListing = ApplicationListing(
            appId = json.readString("appId")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE),
            shortName = json.readString("shortName"),
            status = json.readString("status")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE),
            approvedRevisionId = json.readString("approvedRevisionId"),
            activeSubmissionId = json.readString("activeSubmissionId"),
            reason = json.readString("reason"),
        )
    }
}

internal enum class PublicationAction { SUBMIT, MAKE_PUBLIC }

internal data class PublicationPresentation(
    val label: String,
    val detail: String,
    val action: PublicationAction?,
)

internal data class ManagedApplication(
    val id: String,
    val application: CatalogApp,
    val draft: ApplicationDraft,
    val ownerUid: String?,
    val legacyOwner: String?,
    val publicationStatus: ApplicationPublicationStatus?,
    val ownerMetadataRevisionId: String?,
    val writeVersion: String?,
    val currentRevisionId: String?,
    val publishedSubmissionId: String?,
    val activeSubmissionId: String?,
    val latestSubmission: ApplicationSubmission?,
    val listing: ApplicationListing?,
    val updatedAtMillis: Long,
) {
    val revisionId: String? get() = currentRevisionId ?: publishedSubmissionId

    val marketState: PublicationPresentation
        get() {
            if (publicationStatus == ApplicationPublicationStatus.DELISTED) {
                return PublicationPresentation("作品已下架", "可编辑并保存新版本后重新发布。提交与审核记录仍保留。", null)
            }
            if (publicationStatus == ApplicationPublicationStatus.SUSPENDED) {
                return PublicationPresentation("作品已暂停", "请查看处理意见，再决定是否修改。", null)
            }
            if (draft.audience != ApplicationAudience.PUBLIC) {
                return PublicationPresentation(
                    label = if (draft.audience == ApplicationAudience.OWNER) "仅本人可见" else "工坊坊客可见",
                    detail = "投稿云乐坊会创建公开版本，网站本身的访问保护仍保留。",
                    action = PublicationAction.MAKE_PUBLIC,
                )
            }
            val currentListed = revisionId != null && listing?.approvedRevisionId == revisionId
            if (currentListed && listing?.status == "listed") {
                return PublicationPresentation("已上架云乐坊", "当前版本正在云乐坊公开展示。", null)
            }
            if (currentListed && listing?.status in setOf("suspended", "delisted")) {
                return PublicationPresentation(
                    label = if (listing?.status == "suspended") "云乐坊展示已暂停" else "已从云乐坊下架",
                    detail = listing?.reason ?: "请查看处理意见。",
                    action = null,
                )
            }
            val olderListed = listing?.status == "listed" && !listing.approvedRevisionId.isNullOrEmpty() && !currentListed
            val latest = latestSubmission
            if (revisionId != null && latest != null && latest.id != revisionId) {
                val reviewing = latest.reviewStatus == ApplicationReviewStatus.PENDING ||
                    latest.reviewStatus == ApplicationReviewStatus.IN_REVIEW
                return PublicationPresentation(
                    label = "新版未投稿",
                    detail = if (reviewing) "另一个版本仍在审核；当前版本尚未投稿。" else "这里的审核意见属于另一个版本，当前版本尚未投稿。",
                    action = PublicationAction.SUBMIT,
                )
            }
            when (latest?.reviewStatus) {
                ApplicationReviewStatus.PENDING, ApplicationReviewStatus.IN_REVIEW -> return PublicationPresentation(
                    label = if (latest.reviewStatus == ApplicationReviewStatus.PENDING) "等待审核" else "审核中",
                    detail = if (olderListed) "新版正在审核，云乐坊继续展示上一批准版本。" else "投稿已进入审核流程。",
                    action = null,
                )
                ApplicationReviewStatus.APPROVED -> {
                    val activeSub = listing?.activeSubmissionId ?: activeSubmissionId
                    if (revisionId != null && activeSub == revisionId) {
                        return PublicationPresentation("审核通过", "等待管理员上架到云乐坊。", null)
                    }
                }
                ApplicationReviewStatus.CHANGES_REQUESTED, ApplicationReviewStatus.REJECTED -> return PublicationPresentation(
                    label = if (latest.reviewStatus == ApplicationReviewStatus.REJECTED) "审核未通过" else "需要修改",
                    detail = latest.reviewNote ?: "请修改后重新投稿。",
                    action = PublicationAction.SUBMIT,
                )
                else -> Unit
            }
            return PublicationPresentation(
                label = if (olderListed) "新版未投稿" else "尚未投稿",
                detail = if (olderListed) "云乐坊仍展示上一批准版本，可投稿当前新版。" else "保存当前版本不会自动投稿云乐坊。",
                action = PublicationAction.SUBMIT,
            )
        }

    fun validate(owner: String, expectedId: String? = null) {
        if (writeVersion != null && !PublishingValue.writeVersion(writeVersion)) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        val ownerValid = ownerUid == owner || (ownerUid == null && legacyOwner == owner)
        if (!PublishingValue.identifier(id) ||
            (expectedId != null && id != expectedId) ||
            !ownerValid ||
            application.name.isEmpty() ||
            !CommunityValidation.isValidTimestamp(updatedAtMillis)
        ) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        listing?.let { l ->
            if (l.appId != id || l.status !in setOf("unlisted", "listed", "suspended", "delisted")) {
                throw PublishingException(PublishingError.INVALID_RESPONSE)
            }
        }
        latestSubmission?.let { s ->
            if (s.appId != id ||
                !PublishingValue.identifier(s.id) ||
                s.revision <= 0 ||
                s.submitterUid.trim().isEmpty()
            ) {
                throw PublishingException(PublishingError.INVALID_RESPONSE)
            }
        }
    }

    companion object {
        fun fromJson(json: JSONObject): ManagedApplication {
            val id = json.readString("_id")
                ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            val app = CatalogApp.readScoped(
                record = json,
                allowWorkshopAudience = true,
                allowAuthorizedLaunch = true,
                allowCreatorOwned = true,
            ) ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            val updatedRaw = json.opt("updatedAt")
            if (updatedRaw is Boolean || updatedRaw !is Number || !updatedRaw.toDouble().isFinite() || floor(updatedRaw.toDouble()) != updatedRaw.toDouble()) {
                throw PublishingException(PublishingError.INVALID_RESPONSE)
            }
            val latestSub = if (json.has("latestSubmission") && !json.isNull("latestSubmission")) {
                ApplicationSubmission.fromJson(
                    json.optJSONObject("latestSubmission")
                        ?: throw PublishingException(PublishingError.INVALID_RESPONSE),
                )
            } else {
                null
            }
            val listing = if (json.has("yunlefunListing") && !json.isNull("yunlefunListing")) {
                ApplicationListing.fromJson(
                    json.optJSONObject("yunlefunListing")
                        ?: throw PublishingException(PublishingError.INVALID_RESPONSE),
                )
            } else {
                null
            }
            return ManagedApplication(
                id = id,
                application = app,
                draft = ApplicationDraft.fromJson(json),
                ownerUid = json.readString("ownerUid"),
                legacyOwner = json.readString("_openid"),
                publicationStatus = ApplicationPublicationStatus.fromKey(json.readString("publicationStatus")),
                ownerMetadataRevisionId = json.readString("ownerMetadataRevisionId"),
                writeVersion = json.readString("writeVersion"),
                currentRevisionId = json.readString("currentRevisionId"),
                publishedSubmissionId = json.readString("publishedSubmissionId"),
                activeSubmissionId = json.readString("activeSubmissionId"),
                latestSubmission = latestSub,
                listing = listing,
                updatedAtMillis = updatedRaw.toLong(),
            )
        }
    }
}

internal data class ApplicationSaveReceipt(
    val app: ManagedApplication,
    val submission: ApplicationSubmission,
)

internal data class MarketSubmissionReceipt(
    val appId: String,
    val submissionId: String,
    val reviewStatus: ApplicationReviewStatus,
)
