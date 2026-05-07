package com.mtog.app.session

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID

object DeviceIdentityStore {
    private const val prefsName = "mtog.identity"
    private const val keyDeviceId = "device_id"
    private const val keyAlias = "mtog_identity_p256"

    fun getOrCreateDeviceId(context: Context): String {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val existing = prefs.getString(keyDeviceId, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }

        val generated = UUID.randomUUID().toString()
        prefs.edit().putString(keyDeviceId, generated).apply()
        return generated
    }

    fun getOrCreatePublicKeyBase64(): String {
        val publicKey = loadOrCreateKeyPair().first
        return Base64.encodeToString(x963(publicKey), Base64.NO_WRAP)
    }

    fun deviceName(): String {
        val model = Build.MODEL?.trim().orEmpty()
        return if (model.isNotEmpty()) model else "Galaxy Tab"
    }

    private fun loadOrCreateKeyPair(): Pair<PublicKey, PrivateKey> {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existingCertificate = keyStore.getCertificate(keyAlias)
        val existingPrivateKey = keyStore.getKey(keyAlias, null) as? PrivateKey
        if (existingCertificate != null && existingPrivateKey != null) {
            return existingCertificate.publicKey to existingPrivateKey
        }

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
            .setUserAuthenticationRequired(false)
            .build()
        generator.initialize(spec)
        val pair = generator.generateKeyPair()
        return pair.public to pair.private
    }

    private fun x963(publicKey: PublicKey): ByteArray {
        val ecPublicKey = publicKey as ECPublicKey
        val fieldBytes = (ecPublicKey.params.curve.field.fieldSize + 7) / 8
        val x = normalizeCoordinate(ecPublicKey.w.affineX, fieldBytes)
        val y = normalizeCoordinate(ecPublicKey.w.affineY, fieldBytes)
        return byteArrayOf(0x04) + x + y
    }

    private fun normalizeCoordinate(value: BigInteger, size: Int): ByteArray {
        val bytes = value.toByteArray()
        return when {
            bytes.size == size -> bytes
            bytes.size > size -> bytes.copyOfRange(bytes.size - size, bytes.size)
            else -> ByteArray(size - bytes.size) + bytes
        }
    }
}
