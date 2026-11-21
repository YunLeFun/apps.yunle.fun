package `fun`.yunle.apps.wallet

import android.content.Context
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.account.CloudbaseAuthService
import `fun`.yunle.apps.games.writeAtomicUtf8
import `fun`.yunle.apps.readString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.floor

internal enum class WalletError(val defaultMessage: String) {
    UNAUTHORIZED("登录状态已失效，请重新登录。"),
    FORBIDDEN("当前账号暂不能使用账户服务。"),
    UNAVAILABLE("暂时无法连接账户服务，请检查网络后重试。"),
    INVALID_RESPONSE("账户资料暂时无法核对，请稍后刷新。"),
    IDENTITY_CHANGED("账号已变化，请重新打开钱包。"),
    INVALID_INPUT("钱包参数有误，请重试。"),
    STORAGE("无法安全保存购买归属，请稍后重试。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun message(error: Throwable): String = when (error) {
            is WalletException -> error.error.defaultMessage
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class WalletException(
    val error: WalletError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

private const val MAX_SAFE_INT = 9_007_199_254_740_991L
private const val MAX_WALLET_TIMESTAMP = 253_402_300_799_000L

private fun readStrictLongValue(raw: Any?): Long? {
    if (raw is Boolean || raw !is Number) return null
    val d = raw.toDouble()
    if (!d.isFinite() || floor(d) != d || d < Long.MIN_VALUE.toDouble() || d > Long.MAX_VALUE.toDouble()) {
        return null
    }
    return d.toLong()
}

internal data class WalletSnapshot(
    val coin: Long,
    val membership: Membership,
) {
    data class Membership(
        val isActive: Boolean,
        val level: String?,
        val expireAtMillis: Long?,
    ) {
        val title: String get() = if (level == null || level == "basic") "云乐坊会员" else "会员"
    }

    fun validate() {
        if (coin < 0 || coin > MAX_SAFE_INT) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
        membership.expireAtMillis?.let { exp ->
            if (exp < 0 || exp > MAX_WALLET_TIMESTAMP) throw WalletException(WalletError.INVALID_RESPONSE)
        }
        if (membership.isActive && (membership.level.isNullOrEmpty() || (membership.expireAtMillis ?: 0L) <= 0L)) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): WalletSnapshot {
            val coin = readStrictLongValue(json.opt("coin"))
                ?: throw WalletException(WalletError.INVALID_RESPONSE)
            val memObj = json.optJSONObject("membership")
                ?: throw WalletException(WalletError.INVALID_RESPONSE)
            val isActive = memObj.opt("isActive") as? Boolean
                ?: throw WalletException(WalletError.INVALID_RESPONSE)
            val level = memObj.readString("level")
            val expireAt = if (memObj.has("expireAt") && !memObj.isNull("expireAt")) {
                readStrictLongValue(memObj.opt("expireAt"))
                    ?: throw WalletException(WalletError.INVALID_RESPONSE)
            } else {
                null
            }
            return WalletSnapshot(
                coin = coin,
                membership = Membership(isActive = isActive, level = level, expireAtMillis = expireAt),
            ).also { it.validate() }
        }
    }
}

internal data class CoinLedgerEntry(
    val id: String,
    val userId: String,
    val type: String,
    val amount: Long,
    val balanceAfter: Long,
    val createdAtMillis: Long,
    val appId: String?,
) {
    val title: String
        get() = when (type) {
            "recharge" -> "充值"
            "consume" -> "消费"
            "refund" -> "退款"
            "gift" -> "赠送"
            else -> "账务调整"
        }

    fun validate(owner: String) {
        if (id.isEmpty() ||
            id.length > 200 ||
            userId != owner ||
            amount !in -MAX_SAFE_INT..MAX_SAFE_INT ||
            balanceAfter !in 0L..MAX_SAFE_INT ||
            createdAtMillis !in 0L..MAX_WALLET_TIMESTAMP
        ) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject, owner: String): CoinLedgerEntry {
            return CoinLedgerEntry(
                id = json.readString("_id") ?: json.readString("id")
                    ?: throw WalletException(WalletError.INVALID_RESPONSE),
                userId = json.readString("userId") ?: throw WalletException(WalletError.INVALID_RESPONSE),
                type = json.readString("type") ?: throw WalletException(WalletError.INVALID_RESPONSE),
                amount = readStrictLongValue(json.opt("amount"))
                    ?: throw WalletException(WalletError.INVALID_RESPONSE),
                balanceAfter = readStrictLongValue(json.opt("balanceAfter"))
                    ?: throw WalletException(WalletError.INVALID_RESPONSE),
                createdAtMillis = readStrictLongValue(json.opt("createdAt"))
                    ?: throw WalletException(WalletError.INVALID_RESPONSE),
                appId = json.readString("appId"),
            ).also { it.validate(owner) }
        }
    }
}

internal data class CoinLedgerPage(
    val items: List<CoinLedgerEntry>,
    val nextSkip: Int?,
)

internal data class WalletReconciliation(
    val reconciled: Int,
    val paid: Int,
    val regranted: Int?,
)

internal data class PurchaseVerificationReceipt(
    val granted: Boolean,
    val alreadyProcessed: Boolean,
    val outTradeNo: String,
) {
    fun validate(transactionId: String) {
        if (outTradeNo != "iap_$transactionId" || (!granted && !alreadyProcessed)) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
    }
}

internal interface WalletServing {
    suspend fun account(identity: AuthorizedAccount): WalletSnapshot
    suspend fun transactions(skip: Int, limit: Int, identity: AuthorizedAccount): CoinLedgerPage
    suspend fun reconcile(identity: AuthorizedAccount): WalletReconciliation
    suspend fun verify(transactionId: String, identity: AuthorizedAccount): PurchaseVerificationReceipt
}

internal class WalletService(
    private val gatewayOrigin: String = CloudbaseAuthService.GATEWAY_ORIGIN,
) : WalletServing {
    private val baseUrl = gatewayOrigin.trimEnd('/')

    override suspend fun account(identity: AuthorizedAccount): WalletSnapshot {
        val json = callFunction("account-api", JSONObject().put("action", "getAccount"), identity)
        return WalletSnapshot.fromJson(json)
    }

    override suspend fun transactions(skip: Int, limit: Int, identity: AuthorizedAccount): CoinLedgerPage {
        if (skip !in 0..1_000_000 || limit !in 1..100) {
            throw WalletException(WalletError.INVALID_INPUT)
        }
        val body = JSONObject()
            .put("action", "listTransactions")
            .put("skip", skip)
            .put("limit", limit)
        val json = callFunction("account-api", body, identity)
        val arr = json.optJSONArray("items") ?: throw WalletException(WalletError.INVALID_RESPONSE)
        if (arr.length() > limit) throw WalletException(WalletError.INVALID_RESPONSE)
        val items = (0 until arr.length()).map { idx ->
            val obj = arr.optJSONObject(idx) ?: throw WalletException(WalletError.INVALID_RESPONSE)
            CoinLedgerEntry.fromJson(obj, identity.userID)
        }
        if (items.map { it.id }.toSet().size != items.size) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
        val nextSkip = if (json.has("nextSkip") && !json.isNull("nextSkip")) {
            val valLong = readStrictLongValue(json.opt("nextSkip"))
                ?: throw WalletException(WalletError.INVALID_RESPONSE)
            valLong.toInt()
        } else {
            null
        }
        if (nextSkip != null && (items.size != limit || nextSkip != skip + limit)) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
        return CoinLedgerPage(items = items, nextSkip = nextSkip)
    }

    override suspend fun reconcile(identity: AuthorizedAccount): WalletReconciliation {
        val json = callFunction("wxpay-order", JSONObject().put("action", "reconcileOrders"), identity)
        val reconciled = readStrictLongValue(json.opt("reconciled"))?.toInt()
            ?: throw WalletException(WalletError.INVALID_RESPONSE)
        val paid = readStrictLongValue(json.opt("paid"))?.toInt()
            ?: throw WalletException(WalletError.INVALID_RESPONSE)
        val regranted = if (json.has("regranted") && !json.isNull("regranted")) {
            readStrictLongValue(json.opt("regranted"))?.toInt()
                ?: throw WalletException(WalletError.INVALID_RESPONSE)
        } else {
            null
        }
        if (reconciled !in 0..20 || paid !in 0..reconciled || (regranted != null && regranted !in 0..20)) {
            throw WalletException(WalletError.INVALID_RESPONSE)
        }
        return WalletReconciliation(reconciled = reconciled, paid = paid, regranted = regranted)
    }

    override suspend fun verify(transactionId: String, identity: AuthorizedAccount): PurchaseVerificationReceipt {
        if (!TRANSACTION_ID_RE.matches(transactionId)) {
            throw WalletException(WalletError.INVALID_INPUT)
        }
        val body = JSONObject()
            .put("action", "verifyPurchase")
            .put("transactionId", transactionId)
        val json = callFunction("iap-order", body, identity)
        val granted = json.opt("granted") as? Boolean ?: throw WalletException(WalletError.INVALID_RESPONSE)
        val already = json.opt("alreadyProcessed") as? Boolean ?: false
        val outTradeNo = json.readString("outTradeNo") ?: throw WalletException(WalletError.INVALID_RESPONSE)
        return PurchaseVerificationReceipt(granted, already, outTradeNo).also {
            it.validate(transactionId)
        }
    }

    private suspend fun callFunction(
        function: String,
        fields: JSONObject,
        identity: AuthorizedAccount,
    ): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL("$baseUrl/v1/functions/$function").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            instanceFollowRedirects = false
            useCaches = false
            doOutput = true
            connectTimeout = 25_000
            readTimeout = 45_000
            setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        try {
            conn.outputStream.use { it.write(fields.toString().toByteArray(Charsets.UTF_8)) }
            val status = conn.responseCode
            when (status) {
                401 -> throw WalletException(WalletError.UNAUTHORIZED)
                403 -> throw WalletException(WalletError.FORBIDDEN)
                in 200..299 -> Unit
                else -> throw WalletException(WalletError.UNAVAILABLE)
            }
            val bytes = conn.inputStream.use { stream ->
                val buf = ByteArray(8192)
                val out = ByteArrayOutputStream()
                while (true) {
                    val count = stream.read(buf)
                    if (count == -1) break
                    if (out.size() + count > 2 * 1024 * 1024) {
                        throw WalletException(WalletError.INVALID_RESPONSE)
                    }
                    out.write(buf, 0, count)
                }
                out.toByteArray()
            }
            JSONObject(bytes.toString(Charsets.UTF_8))
        } catch (e: WalletException) {
            throw e
        } catch (t: Throwable) {
            throw WalletException(WalletError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private val TRANSACTION_ID_RE = Regex("^[0-9]{1,32}$")
    }
}

internal object PurchaseAccountToken {
    fun forUser(uid: String): UUID {
        val input = ("fun.yunle.apps.iap-owner.v1\u0000$uid").toByteArray(Charsets.UTF_8)
        val bytes = MessageDigest.getInstance("SHA-256").digest(input).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x80).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02x".format(it) }
        val formatted = "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}"
        return UUID.fromString(formatted)
    }
}

internal class PurchaseOwnershipJournal(
    private val file: File,
) {
    data class Binding(
        val uid: String,
        val confirmed: Boolean,
    )

    private val lock = Any()

    fun owner(orderId: String): String? = synchronized(lock) {
        readLocked()[orderId]?.uid
    }

    fun binding(orderId: String): Binding? = synchronized(lock) {
        readLocked()[orderId]
    }

    fun pendingOrdersFor(uid: String): List<String> = synchronized(lock) {
        readLocked().entries.filter { it.value.uid == uid && !it.value.confirmed }.map { it.key }
    }

    fun reserve(orderId: String, uid: String, allowUnconfirmedReassignment: Boolean = false) {
        writeBinding(orderId, uid, confirmed = false, allowUnconfirmedReassignment = allowUnconfirmedReassignment)
    }

    fun bind(orderId: String, uid: String) {
        writeBinding(orderId, uid, confirmed = true, allowUnconfirmedReassignment = false)
    }

    private fun writeBinding(
        orderId: String,
        uid: String,
        confirmed: Boolean,
        allowUnconfirmedReassignment: Boolean,
    ) = synchronized(lock) {
        if (uid.isEmpty() || !ORDER_ID_RE.matches(orderId)) {
            throw WalletException(WalletError.STORAGE)
        }
        val current = readLocked()
        if (orderId !in current && current.size >= 20_000) {
            throw WalletException(WalletError.STORAGE)
        }
        val previous = current[orderId]
        val canWrite = previous == null ||
            previous.uid == uid ||
            (!previous.confirmed && allowUnconfirmedReassignment)
        if (!canWrite) {
            throw WalletException(WalletError.FORBIDDEN)
        }
        val updated = current.toMutableMap()
        updated[orderId] = Binding(
            uid = uid,
            confirmed = confirmed || (previous?.uid == uid && previous.confirmed),
        )
        val ownersJson = JSONObject().apply {
            updated.forEach { (id, b) ->
                put(id, JSONObject().put("uid", b.uid).put("confirmed", b.confirmed))
            }
        }
        val root = JSONObject().put("version", 2).put("owners", ownersJson)
        try {
            writeAtomicUtf8(file, root.toString())
        } catch (t: Throwable) {
            throw WalletException(WalletError.STORAGE, t)
        }
    }

    private fun readLocked(): Map<String, Binding> {
        if (!file.isFile) return emptyMap()
        return try {
            val root = JSONObject(file.readText(Charsets.UTF_8))
            val version = root.optInt("version", -1)
            val ownersObj = root.optJSONObject("owners") ?: throw WalletException(WalletError.STORAGE)
            val result = linkedMapOf<String, Binding>()
            val keys = ownersObj.keys()
            while (keys.hasNext()) {
                val id = keys.next()
                if (id.isEmpty()) throw WalletException(WalletError.STORAGE)
                when (version) {
                    2 -> {
                        val obj = ownersObj.optJSONObject(id) ?: throw WalletException(WalletError.STORAGE)
                        val uid = obj.readString("uid") ?: throw WalletException(WalletError.STORAGE)
                        val confirmed = obj.opt("confirmed") as? Boolean
                            ?: throw WalletException(WalletError.STORAGE)
                        result[id] = Binding(uid, confirmed)
                    }
                    1 -> {
                        val uid = ownersObj.readString(id) ?: throw WalletException(WalletError.STORAGE)
                        result[id] = Binding(uid, false)
                    }
                    else -> throw WalletException(WalletError.STORAGE)
                }
            }
            if (result.size > 20_000) throw WalletException(WalletError.STORAGE)
            result
        } catch (e: WalletException) {
            throw e
        } catch (t: Throwable) {
            throw WalletException(WalletError.STORAGE, t)
        }
    }

    companion object {
        private val ORDER_ID_RE = Regex("^[A-Za-z0-9_-]{1,64}$")
    }
}

internal interface BillingProvider {
    fun launchRecharge(context: Context, orderRef: String, uid: String)
}

internal class OnlineWebBillingProvider(
    private val journal: PurchaseOwnershipJournal,
    private val onOpenCheckoutUrl: (String) -> Unit,
) : BillingProvider {
    override fun launchRecharge(context: Context, orderRef: String, uid: String) {
        journal.reserve(orderRef, uid, allowUnconfirmedReassignment = false)
        onOpenCheckoutUrl("https://www.yunle.fun/wallet")
    }
}
