package `fun`.yunle.apps.account

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface AccountVault {
    fun read(): ByteArray?
    fun write(data: ByteArray)
}

class InMemoryAccountVault(initial: ByteArray? = null) : AccountVault {
    @Volatile
    private var stored: ByteArray? = initial?.copyOf()

    override fun read(): ByteArray? = stored?.copyOf()

    override fun write(data: ByteArray) {
        stored = data.copyOf()
    }
}

class KeystoreAccountVault(
    private val file: File,
    private val keyAlias: String = "fun.yunle.apps.accounts.vault.v1",
) : AccountVault {
    constructor(context: Context) : this(
        file = File(context.noBackupFilesDir, "accounts/cloudbase-accounts-v1.enc"),
    )

    private val lock = Any()

    override fun read(): ByteArray? = synchronized(lock) {
        if (!file.exists()) return null
        try {
            val payload = file.readBytes()
            if (payload.size <= IV_SIZE_BYTES) throw AccountException(AccountError.STORAGE)
            val iv = payload.copyOfRange(0, IV_SIZE_BYTES)
            val cipherText = payload.copyOfRange(IV_SIZE_BYTES, payload.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
            cipher.doFinal(cipherText)
        } catch (e: AccountException) {
            throw e
        } catch (e: Throwable) {
            throw AccountException(AccountError.STORAGE, e)
        }
    }

    override fun write(data: ByteArray): Unit = synchronized(lock) {
        try {
            val parent = file.parentFile
            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                throw AccountException(AccountError.STORAGE)
            }
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            val iv = cipher.iv
            if (iv == null || iv.size != IV_SIZE_BYTES) {
                throw AccountException(AccountError.STORAGE)
            }
            val encrypted = cipher.doFinal(data)
            val combined = ByteArray(iv.size + encrypted.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(encrypted, 0, combined, iv.size, encrypted.size)

            val tempFile = File(file.parentFile, "${file.name}.tmp")
            tempFile.writeBytes(combined)
            if (!tempFile.renameTo(file)) {
                file.writeBytes(combined)
                tempFile.delete()
            }
        } catch (e: AccountException) {
            throw e
        } catch (e: Throwable) {
            throw AccountException(AccountError.STORAGE, e)
        }
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_SIZE_BYTES = 12
        private const val TAG_LENGTH_BITS = 128
    }
}
