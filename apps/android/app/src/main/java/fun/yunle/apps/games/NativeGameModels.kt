package `fun`.yunle.apps.games

import `fun`.yunle.apps.readString
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlin.math.floor

internal enum class NativeGameError(val defaultMessage: String) {
    INVALID_CATALOG("游戏列表暂时无法读取，请稍后刷新。"),
    UNSUPPORTED_CATALOG("当前版本暂不支持此游戏列表格式。"),
    MODE_UNAVAILABLE("该玩法暂不可用。"),
    INVALID_LAUNCH("游戏启动地址无效。"),
    INVALID_INVITATION("房间号或邀请链接无效，请输入 6 位房间号或云乐坊对局链接。");

    companion object {
        fun message(error: Throwable): String = when (error) {
            is NativeGameException -> error.error.defaultMessage
            is NativePublicRoomException -> error.error.defaultMessage
            is NativeRoomCreationException -> error.error.defaultMessage
            else -> INVALID_CATALOG.defaultMessage
        }
    }
}

internal class NativeGameException(
    val error: NativeGameError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class NativeGamePlayers(
    val min: Int,
    val max: Int,
) {
    val label: String get() = if (min == max) "$min 人" else "$min–$max 人"
}

internal data class NativeGameMode(
    val id: String,
    val title: String,
    val requiresLogin: Boolean,
    val requiresNetwork: Boolean,
    val launchUrl: String,
    val available: Boolean,
    val unavailableReason: String?,
    val orientation: String?,
) {
    companion object {
        val SUPPORTED_IDS = setOf("computer", "local", "online", "tutorial", "pve")

        fun fromJson(json: JSONObject): NativeGameMode = NativeGameMode(
            id = json.readString("id") ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            title = json.readString("title") ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            requiresLogin = json.opt("requiresLogin") as? Boolean
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            requiresNetwork = json.opt("requiresNetwork") as? Boolean
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            launchUrl = json.readString("launchURL")
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            available = json.opt("available") as? Boolean
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
            unavailableReason = json.readString("unavailableReason"),
            orientation = json.readString("orientation"),
        )

        fun toJson(mode: NativeGameMode): JSONObject = JSONObject()
            .put("id", mode.id)
            .put("title", mode.title)
            .put("requiresLogin", mode.requiresLogin)
            .put("requiresNetwork", mode.requiresNetwork)
            .put("launchURL", mode.launchUrl)
            .put("available", mode.available)
            .put("unavailableReason", mode.unavailableReason ?: JSONObject.NULL)
            .put("orientation", mode.orientation ?: JSONObject.NULL)
    }
}

internal data class NativeGame(
    val gameId: String,
    val appId: String,
    val name: String,
    val description: String,
    val iconUrl: String?,
    val lifecycle: String,
    val launchModes: List<NativeGameMode>,
    val resourceManifestUrl: String?,
    val players: NativeGamePlayers?,
    val type: String?,
    val fallbackUrl: String?,
    val resourceVersion: String?,
) {
    val id: String get() = gameId
    val isPlayable: Boolean get() = lifecycle == "playable" || lifecycle == "beta"
    val availableModes: List<NativeGameMode> get() = if (isPlayable) launchModes.filter { it.available } else emptyList()
    val matchesFirstRelease: Boolean get() = gameId in FIRST_RELEASE_IDS

    fun mode(id: String): NativeGameMode? = launchModes.firstOrNull { it.id == id }

    fun launchUrl(mode: NativeGameMode): String {
        if (!launchModes.contains(mode) || !isPlayable || !mode.available) {
            throw NativeGameException(NativeGameError.MODE_UNAVAILABLE)
        }
        return validatedLaunchUrl(mode.launchUrl, gameId = gameId, modeId = mode.id)
    }

    fun validate() {
        if (!validIdentifier(gameId) ||
            !validIdentifier(appId) ||
            name.isEmpty() ||
            name.length > 80 ||
            description.length > 2000 ||
            lifecycle !in setOf("playable", "beta", "coming-soon", "retired") ||
            launchModes.isEmpty() ||
            launchModes.size > 8
        ) {
            throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        if (gameId in FIRST_RELEASE_IDS && appId != gameId) {
            throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        players?.let { p ->
            if (p.min <= 0 || p.min > p.max || p.max > 16) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
        }
        iconUrl?.let { icon ->
            if (!isPublicHttps(icon)) throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        resourceManifestUrl?.let { manifest ->
            val uri = parsePublicHttps(manifest) ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun" ||
                uri.rawPath != "/native/resources/$gameId-v1.json" ||
                uri.rawQuery != null ||
                uri.rawFragment != null
            ) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
        }
        resourceVersion?.let { ver ->
            if (!SHA256_HEX_RE.matches(ver)) throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        fallbackUrl?.let { fb ->
            val uri = parsePublicHttps(fb) ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun" ||
                uri.rawPath != "/games/$gameId" ||
                uri.rawQuery != null ||
                uri.rawFragment != null
            ) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
        }
        val modeIds = mutableSetOf<String>()
        for (mode in launchModes) {
            if (mode.id !in NativeGameMode.SUPPORTED_IDS ||
                !modeIds.add(mode.id) ||
                mode.title.isEmpty() ||
                mode.title.length > 80 ||
                (mode.unavailableReason?.length ?: 0) > 240 ||
                (mode.orientation != null && mode.orientation !in setOf("portrait", "landscape", "system"))
            ) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            validatedLaunchUrl(mode.launchUrl, gameId = gameId, modeId = mode.id)
            if (mode.id == "online" && (!mode.requiresLogin || !mode.requiresNetwork)) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            if (!isPlayable && mode.available) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
        }
    }

    companion object {
        val FIRST_RELEASE_IDS = setOf("gomoku", "flight-chess", "paper-star")
        private val IDENTIFIER_RE = Regex("^[a-z][a-z0-9-]{0,63}$")
        private val SHA256_HEX_RE = Regex("^[0-9a-f]{64}$")

        fun validIdentifier(value: String): Boolean = IDENTIFIER_RE.matches(value)

        fun parsePublicHttps(raw: String): URI? {
            if (raw.any { it.code <= 32 || it.code in 127..159 }) return null
            val uri = runCatching { URI(raw) }.getOrNull() ?: return null
            val host = uri.host ?: return null
            if (!uri.scheme.equals("https", ignoreCase = true) ||
                host.isEmpty() ||
                uri.rawUserInfo != null ||
                uri.port !in listOf(-1, 443)
            ) {
                return null
            }
            return uri
        }

        fun isPublicHttps(raw: String): Boolean = parsePublicHttps(raw) != null

        fun validatedLaunchUrl(value: String, gameId: String, modeId: String): String {
            if (!validIdentifier(gameId) || modeId !in NativeGameMode.SUPPORTED_IDS) {
                throw NativeGameException(NativeGameError.INVALID_LAUNCH)
            }
            val uri = parsePublicHttps(value) ?: throw NativeGameException(NativeGameError.INVALID_LAUNCH)
            if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun" ||
                uri.rawPath != "/games/$gameId/$modeId" ||
                uri.rawQuery != null ||
                uri.rawFragment != null
            ) {
                throw NativeGameException(NativeGameError.INVALID_LAUNCH)
            }
            return value
        }

        fun fromJson(json: JSONObject): NativeGame {
            val playersObj = json.optJSONObject("players")
            val players = playersObj?.let { p ->
                val minRaw = p.opt("min")
                val maxRaw = p.opt("max")
                if (minRaw is Boolean || minRaw !is Number || maxRaw is Boolean || maxRaw !is Number) {
                    throw NativeGameException(NativeGameError.INVALID_CATALOG)
                }
                NativeGamePlayers(min = minRaw.toInt(), max = maxRaw.toInt())
            }
            val modesArr = json.optJSONArray("launchModes")
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            val modes = (0 until modesArr.length()).map { i ->
                val obj = modesArr.optJSONObject(i)
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
                NativeGameMode.fromJson(obj)
            }
            return NativeGame(
                gameId = json.readString("gameId")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                appId = json.readString("appId")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                name = json.readString("name")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                description = json.readString("description").orEmpty(),
                iconUrl = json.readString("iconURL"),
                lifecycle = json.readString("lifecycle")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                launchModes = modes,
                resourceManifestUrl = json.readString("resourceManifestURL"),
                players = players,
                type = json.readString("type"),
                fallbackUrl = json.readString("fallbackURL"),
                resourceVersion = json.readString("resourceVersion"),
            )
        }

        fun toJson(game: NativeGame): JSONObject = JSONObject().apply {
            put("gameId", game.gameId)
            put("appId", game.appId)
            put("name", game.name)
            put("description", game.description)
            put("iconURL", game.iconUrl ?: JSONObject.NULL)
            put("lifecycle", game.lifecycle)
            put("launchModes", JSONArray(game.launchModes.map(NativeGameMode::toJson)))
            put("resourceManifestURL", game.resourceManifestUrl ?: JSONObject.NULL)
            put(
                "players",
                game.players?.let { JSONObject().put("min", it.min).put("max", it.max) } ?: JSONObject.NULL,
            )
            put("type", game.type ?: JSONObject.NULL)
            put("fallbackURL", game.fallbackUrl ?: JSONObject.NULL)
            put("resourceVersion", game.resourceVersion ?: JSONObject.NULL)
        }
    }
}

internal data class NativeGameCatalog(
    val schemaVersion: Int,
    val catalogVersion: String,
    val generatedAt: String,
    val games: List<NativeGame>,
) {
    fun validate() {
        if (schemaVersion != 1) throw NativeGameException(NativeGameError.UNSUPPORTED_CATALOG)
        val generatedOk = runCatching { Instant.parse(generatedAt) }.isSuccess
        if (catalogVersion.isEmpty() || catalogVersion.length > 128 || games.size > 64 || !generatedOk) {
            throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        val seenGames = mutableSetOf<String>()
        val seenApps = mutableSetOf<String>()
        for (game in games) {
            if (!seenGames.add(game.gameId) || !seenApps.add(game.appId)) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            game.validate()
        }
    }

    fun toJsonString(): String = JSONObject().apply {
        put("schemaVersion", schemaVersion)
        put("catalogVersion", catalogVersion)
        put("generatedAt", generatedAt)
        put("games", JSONArray(games.map(NativeGame::toJson)))
    }.toString()

    companion object {
        fun decode(payload: String): NativeGameCatalog {
            if (payload.toByteArray(Charsets.UTF_8).size > 1_048_576) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            val root = runCatching { JSONObject(payload) }.getOrNull()
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            val versionRaw = root.opt("schemaVersion")
            if (versionRaw is Boolean || versionRaw !is Number || floor(versionRaw.toDouble()) != versionRaw.toDouble()) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            val gamesArr = root.optJSONArray("games")
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            val games = (0 until gamesArr.length()).map { i ->
                val obj = gamesArr.optJSONObject(i)
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
                NativeGame.fromJson(obj)
            }
            return NativeGameCatalog(
                schemaVersion = versionRaw.toInt(),
                catalogVersion = root.readString("catalogVersion")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                generatedAt = root.readString("generatedAt")
                    ?: throw NativeGameException(NativeGameError.INVALID_CATALOG),
                games = games,
            ).also { it.validate() }
        }
    }
}

internal data class NativeGameRoomIntent(
    val inviteCode: String,
    val role: Role = Role.PLAYER,
) {
    enum class Role(val key: String, val label: String) {
        PLAYER("player", "玩家加入"),
        SPECTATOR("spectator", "旁观观战");

        companion object {
            fun fromKey(raw: String?): Role? = entries.firstOrNull { it.key == raw }
        }
    }

    val url: String
        get() = if (role == Role.SPECTATOR) {
            "https://play.yunle.fun/room/$inviteCode?role=spectator"
        } else {
            "https://play.yunle.fun/room/$inviteCode"
        }

    companion object {
        private val CODE_RE = Regex("^[A-Z0-9]{6}$")

        fun validCode(value: String): Boolean = CODE_RE.matches(value)

        fun parseUrl(raw: String): NativeGameRoomIntent? {
            val uri = NativeGame.parsePublicHttps(raw) ?: return null
            if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun" || uri.rawFragment != null) {
                return null
            }
            val path = uri.rawPath.orEmpty()
            val prefix = "/room/"
            if (!path.startsWith(prefix)) return null
            val code = path.removePrefix(prefix)
            if (!validCode(code)) return null
            val rawQuery = uri.rawQuery
            var parsedRole = Role.PLAYER
            if (!rawQuery.isNullOrEmpty()) {
                val pairs = rawQuery.split('&')
                if (pairs.size > 1) return null
                for (pair in pairs) {
                    val idx = pair.indexOf('=')
                    if (idx <= 0) return null
                    val k = pair.substring(0, idx)
                    val v = URLDecoder.decode(pair.substring(idx + 1), Charsets.UTF_8.name())
                    if (k != "role") return null
                    parsedRole = Role.fromKey(v) ?: return null
                }
            }
            return NativeGameRoomIntent(inviteCode = code, role = parsedRole)
        }

        fun parseInput(input: String, role: Role = Role.PLAYER): NativeGameRoomIntent {
            val value = input.trim()
            if (value.contains("://")) {
                return parseUrl(value) ?: throw NativeGameException(NativeGameError.INVALID_INVITATION)
            }
            val code = value.uppercase(Locale.ROOT)
            if (!validCode(code)) throw NativeGameException(NativeGameError.INVALID_INVITATION)
            return NativeGameRoomIntent(inviteCode = code, role = role)
        }
    }
}

internal enum class NativePublicRoomError(val defaultMessage: String) {
    INVALID_RESPONSE("暂时无法读取公开房间，请稍后刷新。"),
    UNAVAILABLE("公开房间暂时不可用，请稍后重试，也可以凭房间号加入。");
}

internal class NativePublicRoomException(
    val error: NativePublicRoomError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class NativePublicRoom(
    val inviteCode: String,
    val gameId: String?,
    val status: Status,
    val memberCount: Int,
    val capacity: Int,
) {
    enum class Status(val key: String, val label: String) {
        WAITING("waiting", "等待玩家"),
        PLAYING("playing", "对局进行中"),
        COMPLETED("completed", "等待下一局");

        companion object {
            fun fromKey(raw: String?): Status =
                entries.firstOrNull { it.key == raw }
                    ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
        }
    }

    val isSpectating: Boolean get() = status == Status.PLAYING
    val actionTitle: String get() = if (isSpectating) "观战" else "加入房间"

    fun intent(): NativeGameRoomIntent = NativeGameRoomIntent(
        inviteCode = inviteCode,
        role = if (isSpectating) NativeGameRoomIntent.Role.SPECTATOR else NativeGameRoomIntent.Role.PLAYER,
    )

    fun gameName(games: List<NativeGame>): String {
        val id = gameId ?: return "一起选游戏"
        return games.firstOrNull { it.gameId == id }?.name
            ?: EXTRA_GAME_NAMES[id]
            ?: "联机游戏"
    }

    companion object {
        private val EXTRA_GAME_NAMES = mapOf(
            "stone-chess" to "石子棋",
            "animal-chess" to "斗兽棋",
            "dark-animal-chess" to "暗兽棋",
            "ganyandyan" to "干瞪眼",
            "snake" to "联机贪吃蛇",
        )

        fun decodeList(payload: String): List<NativePublicRoom> {
            if (payload.toByteArray(Charsets.UTF_8).size > 65_536) {
                throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            }
            val root = runCatching { JSONObject(payload) }.getOrNull()
                ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            if (root.opt("ok") != true) {
                throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            }
            val arr = root.optJSONArray("rooms")
                ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            if (arr.length() > 50) throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            val seen = mutableSetOf<String>()
            val result = ArrayList<NativePublicRoom>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i)
                    ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
                val code = obj.readString("inviteCode")
                    ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
                val gameId = obj.readString("gameId")
                val status = Status.fromKey(obj.readString("status"))
                val countRaw = obj.opt("memberCount")
                val capRaw = obj.opt("capacity")
                if (countRaw is Boolean || countRaw !is Number || capRaw is Boolean || capRaw !is Number) {
                    throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
                }
                val count = countRaw.toInt()
                val capacity = capRaw.toInt()
                if (!NativeGameRoomIntent.validCode(code) ||
                    !seen.add(code) ||
                    (gameId != null && !NativeGame.validIdentifier(gameId)) ||
                    capacity !in setOf(4, 8) ||
                    count !in 1 until capacity
                ) {
                    throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
                }
                result.add(
                    NativePublicRoom(
                        inviteCode = code,
                        gameId = gameId,
                        status = status,
                        memberCount = count,
                        capacity = capacity,
                    ),
                )
            }
            return result
        }
    }
}

internal enum class NativeRoomCreationError(val defaultMessage: String) {
    UNAUTHORIZED("登录已失效，请重新登录后再试。"),
    IDENTITY_CHANGED("账号已变化，请重新打开创建房间。"),
    CONSENT_REQUIRED("需要允许云乐坊间使用当前账号的标识、昵称和头像后继续。"),
    INVALID_RESPONSE("暂时无法确认创房结果。请重试，同一次操作会沿用原请求，避免重复创建。"),
    INVALID_INPUT("这个游戏暂不支持原生创房，请重新选择。"),
    FORBIDDEN("当前账号暂时无法创房，请确认账号状态及手机号验证。"),
    UNAVAILABLE("暂时无法确认创房结果。请重试，同一次操作会沿用原请求，避免重复创建。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED
}

internal class NativeRoomCreationException(
    val error: NativeRoomCreationError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class NativeRoomCreationDraft(
    val gameId: String? = null,
    val isPublic: Boolean = false,
) {
    fun payloadJson(): String {
        val obj = JSONObject()
            .put("roomCapacity", 4)
            .put("visibility", if (isPublic) "public" else "private")
        val targetGame = gameId
        if (targetGame != null) {
            val ruleset = RULESETS[targetGame]
                ?: throw NativeRoomCreationException(NativeRoomCreationError.INVALID_INPUT)
            obj.put(
                "game",
                JSONObject()
                    .put("gameId", targetGame)
                    .put("rulesetId", ruleset)
                    .put("rulesetVersion", 1),
            )
        } else {
            obj.put("game", JSONObject.NULL)
        }
        return obj.toString()
    }

    companion object {
        val RULESETS = mapOf(
            "gomoku" to "freestyle-15",
            "stone-chess" to "erdingyi-4",
            "animal-chess" to "classic-7x9",
            "dark-animal-chess" to "basic-4x4",
            "flight-chess" to "classic-4",
            "ganyandyan" to "classic-wild",
            "snake" to "arena-24-v1",
        )
    }
}

internal data class NativeGameLaunchContext(
    val launchId: UUID,
    val gameId: String,
    val modeId: String,
)

internal data class NativeGameLifecycleEvent(
    val schemaVersion: Int,
    val launchId: UUID,
    val gameId: String,
    val modeId: String,
    val state: State,
    val room: Room?,
    val elapsedMilliseconds: Double?,
) {
    enum class State(val key: String) {
        READY("ready"),
        FAILED("failed"),
        CONNECTING("connecting"),
        ROOM_READY("room-ready"),
        ROOM_STATE("room-state"),
        ROOM_LEFT("room-left");

        companion object {
            fun fromKey(raw: String?): State? = entries.firstOrNull { it.key == raw }
        }
    }

    data class Room(
        val inviteCode: String,
        val role: String,
        val state: String?,
        val gameId: String?,
    )

    companion object {
        fun parse(
            json: JSONObject,
            sourceOrigin: String,
            expectedLaunchId: UUID,
            expectedGameId: String,
            expectedModeId: String,
            expectedOrigin: String = "https://play.yunle.fun",
        ): NativeGameLifecycleEvent? {
            if (!originsEqual(sourceOrigin, expectedOrigin)) return null
            if (json.toString().toByteArray(Charsets.UTF_8).size > 8192) return null
            val svRaw = json.opt("schemaVersion")
            if (svRaw is Boolean || svRaw !is Number || svRaw.toInt() != 1) return null
            val launchStr = json.readString("launchId") ?: return null
            val parsedLaunchId = runCatching { UUID.fromString(launchStr) }.getOrNull() ?: return null
            if (parsedLaunchId != expectedLaunchId) return null
            val gId = json.readString("gameId") ?: return null
            val mId = json.readString("modeId") ?: return null
            if (gId != expectedGameId || mId != expectedModeId) return null
            val state = State.fromKey(json.readString("state")) ?: return null
            val elapsed = if (json.has("elapsedMilliseconds") && !json.isNull("elapsedMilliseconds")) {
                val raw = json.opt("elapsedMilliseconds")
                if (raw is Boolean || raw !is Number) return null
                val d = raw.toDouble()
                if (!d.isFinite() || d < 0.0 || d > 24.0 * 60.0 * 60.0 * 1000.0) return null
                d
            } else {
                null
            }
            val room = if (json.has("room") && !json.isNull("room")) {
                val rObj = json.optJSONObject("room") ?: return null
                val code = rObj.readString("inviteCode") ?: return null
                val role = rObj.readString("role") ?: return null
                val roomState = rObj.readString("state")
                val roomGameId = rObj.readString("gameId")
                if (!NativeGameRoomIntent.validCode(code) ||
                    role !in setOf("player", "spectator") ||
                    (roomState != null && (roomState.toByteArray(Charsets.UTF_8).size > 64 || roomState.any { it.code < 32 })) ||
                    (roomGameId != null && !NativeGame.validIdentifier(roomGameId))
                ) {
                    return null
                }
                Room(inviteCode = code, role = role, state = roomState, gameId = roomGameId)
            } else {
                null
            }
            return NativeGameLifecycleEvent(
                schemaVersion = 1,
                launchId = parsedLaunchId,
                gameId = gId,
                modeId = mId,
                state = state,
                room = room,
                elapsedMilliseconds = elapsed,
            )
        }

        private fun originsEqual(a: String, b: String): Boolean {
            val uA = runCatching { URI(a) }.getOrNull() ?: return false
            val uB = runCatching { URI(b) }.getOrNull() ?: return false
            val portA = if (uA.port != -1) uA.port else if (uA.scheme.equals("https", true)) 443 else 80
            val portB = if (uB.port != -1) uB.port else if (uB.scheme.equals("https", true)) 443 else 80
            return uA.scheme.equals(uB.scheme, ignoreCase = true) &&
                uA.host.orEmpty().equals(uB.host.orEmpty(), ignoreCase = true) &&
                portA == portB &&
                uA.rawUserInfo == null
        }
    }
}

internal object NativeGameLaunchUrl {
    private val SLUG_RE = Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$")
    private val ROOM_PATH_RE = Regex("^/room/[A-Z0-9]{6}$")
    private val GAME_PATH_RE = Regex("^/games/[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)?$")

    fun publicUrl(raw: String): String? {
        val uri = NativeGame.parsePublicHttps(raw) ?: return null
        if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun") return null
        val path = uri.rawPath.orEmpty()
        val isRoom = ROOM_PATH_RE.matches(path)
        val isGame = GAME_PATH_RE.matches(path)
        if (!isRoom && !isGame) return null
        val hasSpectator = isRoom && uri.rawQuery?.split('&')?.any { it == "role=spectator" } == true
        return buildString {
            append("https://play.yunle.fun")
            append(path)
            if (hasSpectator) append("?role=spectator")
        }
    }

    fun addingContext(raw: String, launchId: UUID, gameId: String, modeId: String): String? {
        val uri = NativeGame.parsePublicHttps(raw) ?: return null
        if (uri.host?.lowercase(Locale.ROOT) != "play.yunle.fun" ||
            uri.rawFragment != null ||
            !SLUG_RE.matches(gameId) ||
            !SLUG_RE.matches(modeId)
        ) {
            return null
        }
        val reserved = setOf("ylfLaunchId", "ylfGameId", "ylfMode")
        val existing = uri.rawQuery.orEmpty().split('&').filter { it.isNotEmpty() }
        if (existing.any { pair -> pair.substringBefore('=') in reserved }) return null
        val added = listOf(
            "ylfLaunchId=${launchId}",
            "ylfGameId=$gameId",
            "ylfMode=$modeId",
        )
        val query = (existing + added).joinToString("&")
        val path = uri.rawPath.orEmpty()
        return "https://play.yunle.fun$path?$query"
    }

    fun extractContext(raw: String): NativeGameLaunchContext? {
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val query = uri.rawQuery ?: return null
        val params = linkedMapOf<String, String>()
        for (pair in query.split('&')) {
            val idx = pair.indexOf('=')
            if (idx <= 0) continue
            val k = pair.substring(0, idx)
            val v = runCatching { URLDecoder.decode(pair.substring(idx + 1), Charsets.UTF_8.name()) }.getOrNull()
                ?: continue
            params[k] = v
        }
        val launchId = runCatching { UUID.fromString(params["ylfLaunchId"]) }.getOrNull() ?: return null
        val gameId = params["ylfGameId"]?.takeIf(NativeGame::validIdentifier) ?: return null
        val modeId = params["ylfMode"]?.takeIf { it in NativeGameMode.SUPPORTED_IDS } ?: return null
        return NativeGameLaunchContext(launchId = launchId, gameId = gameId, modeId = modeId)
    }
}
