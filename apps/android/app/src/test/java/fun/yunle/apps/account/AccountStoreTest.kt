package `fun`.yunle.apps.account

import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeAccountApi : AccountAuthenticating {
    val usersByToken = mutableMapOf<String, AccountUser>()
    var refreshCounter = 0

    override suspend fun passwordSignIn(
        identifier: String,
        password: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse {
        val id = when {
            identifier.contains("alice") -> "user_alice"
            identifier.contains("bob") -> "user_bob"
            else -> throw AccountException(AccountError.INVALID_CREDENTIALS)
        }
        val token = "acc_${id}_${++refreshCounter}"
        usersByToken[token] = AccountUser(id = id, name = identifier, username = identifier)
        return AuthTokenResponse(
            accessToken = token,
            refreshToken = "ref_${id}_$refreshCounter",
            expiresIn = 3600,
            subject = id,
        )
    }

    override suspend fun sendVerification(
        address: VerificationAddress,
        deviceID: String,
        captcha: String?,
    ): VerificationChallenge = VerificationChallenge(
        address = address,
        id = "ver_1",
        isExistingUser = true,
        expiresAtMillis = System.currentTimeMillis() + 60_000L,
    )

    override suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse {
        val token = "acc_otp_${++refreshCounter}"
        usersByToken[token] = AccountUser(id = "user_otp", name = "OTP User")
        return AuthTokenResponse(
            accessToken = token,
            refreshToken = "ref_otp_$refreshCounter",
            expiresIn = 3600,
            subject = "user_otp",
        )
    }

    override suspend fun refresh(refreshToken: String, deviceID: String): AuthTokenResponse {
        val uid = refreshToken.split("_")[1].let { "user_$it" }
        val token = "acc_${uid}_${++refreshCounter}"
        usersByToken[token] = AccountUser(id = uid, name = uid)
        return AuthTokenResponse(
            accessToken = token,
            refreshToken = "ref_${uid.removePrefix("user_")}_$refreshCounter",
            expiresIn = 3600,
            subject = uid,
        )
    }

    override suspend fun user(accessToken: String, deviceID: String): AccountUser =
        usersByToken[accessToken] ?: throw AccountException(AccountError.EXPIRED_SESSION)

    override suspend fun signOut(accessToken: String, deviceID: String) {}

    override suspend fun updateProfile(
        userID: String,
        name: String,
        description: String,
        accessToken: String,
        deviceID: String,
    ) {
        val current = usersByToken[accessToken] ?: throw AccountException(AccountError.EXPIRED_SESSION)
        usersByToken[accessToken] = current.copy(name = name, description = description)
    }

    override suspend fun captcha(deviceID: String): CaptchaImage =
        CaptchaImage(data = "data:image/png;base64,", type = "image", token = "tok", expiresIn = 120)

    override suspend fun verifyCaptcha(token: String, text: String, deviceID: String): String =
        "verified_captcha"
}

class AccountStoreTest {
    @Test
    fun `sign in switch and remove track identityGeneration and vault persistence`() = runBlocking {
        val vault = InMemoryAccountVault()
        val api = FakeAccountApi()
        val retiredIds = mutableListOf<String>()
        val identityHistory = mutableListOf<String?>()

        val store = AccountStore(
            session = AccountSession(api = api, vault = vault),
            accountWillRemove = { retiredIds += it },
            identityDidChange = { identityHistory += it },
        )

        store.passwordSignIn(identifier = "alice", password = "secret")
        assertEquals("user_alice", store.user?.id)
        val genAlice1 = store.identityGeneration.value

        store.passwordSignIn(identifier = "bob", password = "secret")
        assertEquals("user_bob", store.user?.id)
        val genBob = store.identityGeneration.value
        assertNotEquals(genAlice1, genBob)

        // Switching back to A advances identityGeneration so stale requests are rejected
        store.select("user_alice")
        assertEquals("user_alice", store.user?.id)
        val genAlice2 = store.identityGeneration.value
        assertNotEquals(genAlice1, genAlice2)

        store.updateProfile(name = "Alice Updated", description = "Builder")
        assertEquals("Alice Updated", store.user?.name)
        assertEquals("Builder", store.user?.description)

        store.remove("user_alice")
        assertNull(store.user)
        assertTrue("user_alice" in retiredIds)
        assertEquals(listOf("user_alice", "user_bob", "user_alice", null), identityHistory)

        // Vault survives store recreation with remaining saved account (Bob)
        val reloaded = AccountStore(session = AccountSession(api = api, vault = vault))
        reloaded.prepareInitialRestore()
        reloaded.consumeInitialRestore()
        assertEquals(listOf("user_bob"), reloaded.overview.value.users.map { it.id })
    }

    @Test
    fun `phone normalization drops mainland prefix and formats cleanly`() {
        val addr = VerificationAddress.phoneInput("+86 138-0013-8000")
        assertTrue(addr is VerificationAddress.Phone)
        assertEquals("+86 13800138000", (addr as VerificationAddress.Phone).number)
    }

    @Test
    fun `same generation does not advance without active user change`() = runBlocking {
        val store = AccountStore(session = AccountSession(api = FakeAccountApi(), vault = InMemoryAccountVault()))
        val initialGen: UUID = store.identityGeneration.value
        store.prepareInitialRestore()
        store.consumeInitialRestore()
        assertNull(store.user)
        assertEquals(initialGen, store.identityGeneration.value)
    }
}
