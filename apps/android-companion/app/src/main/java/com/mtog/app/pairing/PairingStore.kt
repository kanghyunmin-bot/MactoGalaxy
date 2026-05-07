package com.mtog.app.pairing

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject

data class TrustedPeerRecord(
    val deviceId: String,
    val deviceName: String,
    val publicKeyBase64: String,
    val pairedAtEpochMs: Long,
    val lastSeenAtEpochMs: Long
)

data class PairingUiState(
    val enteredCode: String = "1408",
    val statusText: String = "Enter the same 4-digit code on both devices",
    val trustedPeerCount: Int = 0,
    val lastTrustedPeerName: String = "No trusted peer"
) {
    val isCodeComplete: Boolean
        get() = enteredCode.length == 4
}

object PairingStore {
    private const val prefsName = "mtog.pairing"
    private const val keyEnteredCode = "entered_code"
    private const val keyTrustedPeers = "trusted_peers"

    private var appContext: Context? = null
    private val _state = MutableStateFlow(PairingUiState())
    val state: StateFlow<PairingUiState> = _state

    fun initialize(context: Context) {
        appContext = context.applicationContext
        val prefs = prefs()
        val peers = loadTrustedPeers()
        _state.value = PairingUiState(
            enteredCode = prefs.getString(keyEnteredCode, "1408").orEmpty().ifBlank { "1408" },
            statusText = if (peers.isEmpty()) {
                "Enter the same 4-digit code on both devices"
            } else {
                "Trusted reconnect available"
            },
            trustedPeerCount = peers.size,
            lastTrustedPeerName = peers.maxByOrNull { it.lastSeenAtEpochMs }?.deviceName ?: "No trusted peer"
        )
    }

    fun updateEnteredCode(code: String) {
        val normalized = code.filter(Char::isDigit).take(4)
        prefs().edit().putString(keyEnteredCode, normalized).apply()
        _state.update {
            it.copy(
                enteredCode = normalized,
                statusText = if (normalized.length == 4) {
                    "Code saved locally. Pair from the Mac app when connected."
                } else {
                    "Enter all 4 digits on both devices"
                }
            )
        }
    }

    fun currentCode(): String {
        return prefs().getString(keyEnteredCode, "").orEmpty()
    }

    fun isTrustedPeer(deviceId: String, publicKeyBase64: String): Boolean {
        return loadTrustedPeers().any { it.deviceId == deviceId && it.publicKeyBase64 == publicKeyBase64 }
    }

    fun upsertTrustedPeer(deviceId: String, deviceName: String, publicKeyBase64: String) {
        val now = System.currentTimeMillis()
        val peers = loadTrustedPeers().toMutableList()
        val index = peers.indexOfFirst { it.deviceId == deviceId }
        val updated = if (index >= 0) {
            peers[index].copy(
                deviceName = deviceName,
                publicKeyBase64 = publicKeyBase64,
                lastSeenAtEpochMs = now
            )
        } else {
            TrustedPeerRecord(
                deviceId = deviceId,
                deviceName = deviceName,
                publicKeyBase64 = publicKeyBase64,
                pairedAtEpochMs = now,
                lastSeenAtEpochMs = now
            )
        }

        if (index >= 0) {
            peers[index] = updated
        } else {
            peers += updated
        }

        saveTrustedPeers(peers)
        _state.update {
            it.copy(
                statusText = "Trusted device stored for $deviceName",
                trustedPeerCount = peers.size,
                lastTrustedPeerName = deviceName
            )
        }
    }

    fun markPeerSeen(deviceName: String, trusted: Boolean) {
        _state.update {
            it.copy(
                statusText = if (trusted) {
                    "Trusted reconnect active with $deviceName"
                } else {
                    "Connected peer requires 4-digit pairing"
                },
                lastTrustedPeerName = if (trusted) deviceName else it.lastTrustedPeerName
            )
        }
    }

    fun markStatus(text: String) {
        _state.update { it.copy(statusText = text) }
    }

    private fun prefs() = requireNotNull(appContext) {
        "PairingStore.initialize(context) must be called before use"
    }.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun loadTrustedPeers(): List<TrustedPeerRecord> {
        val encoded = prefs().getString(keyTrustedPeers, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(encoded)
            buildList {
                repeat(array.length()) { index ->
                    val item = array.getJSONObject(index)
                    add(
                        TrustedPeerRecord(
                            deviceId = item.getString("deviceId"),
                            deviceName = item.getString("deviceName"),
                            publicKeyBase64 = item.getString("publicKeyBase64"),
                            pairedAtEpochMs = item.getLong("pairedAtEpochMs"),
                            lastSeenAtEpochMs = item.getLong("lastSeenAtEpochMs")
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun saveTrustedPeers(peers: List<TrustedPeerRecord>) {
        val array = JSONArray()
        peers.forEach { peer ->
            array.put(
                JSONObject()
                    .put("deviceId", peer.deviceId)
                    .put("deviceName", peer.deviceName)
                    .put("publicKeyBase64", peer.publicKeyBase64)
                    .put("pairedAtEpochMs", peer.pairedAtEpochMs)
                    .put("lastSeenAtEpochMs", peer.lastSeenAtEpochMs)
            )
        }
        prefs().edit().putString(keyTrustedPeers, array.toString()).apply()
    }
}
