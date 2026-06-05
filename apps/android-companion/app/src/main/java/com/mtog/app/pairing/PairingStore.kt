package com.mtog.app.pairing

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject
import kotlin.random.Random

data class TrustedPeerRecord(
    val deviceId: String,
    val deviceName: String,
    val publicKeyBase64: String,
    val pairedAtEpochMs: Long,
    val lastSeenAtEpochMs: Long
)

data class PairingUiState(
    val enteredCode: String = "",
    val statusText: String = "갤럭시에 표시된 4자리 코드를 Mac에 입력하세요",
    val trustedPeerCount: Int = 0,
    val lastTrustedPeerName: String = "저장된 기기 없음"
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
        val existingCode = prefs.getString(keyEnteredCode, null)
            .orEmpty()
            .filter(Char::isDigit)
            .take(4)
            .takeIf { it.length == 4 && it != "1408" }
        val pairingCode = existingCode ?: generateAndPersistPairingCode()
        _state.value = PairingUiState(
            enteredCode = pairingCode,
            statusText = if (peers.isEmpty()) {
                "이 4자리 코드를 Mac 앱에 입력하세요"
            } else {
                "저장된 기기와 다시 연결할 수 있습니다"
            },
            trustedPeerCount = peers.size,
            lastTrustedPeerName = peers.maxByOrNull { it.lastSeenAtEpochMs }?.deviceName ?: "저장된 기기 없음"
        )
    }

    fun updateEnteredCode(code: String) {
        val normalized = code.filter(Char::isDigit).take(4)
        prefs().edit().putString(keyEnteredCode, normalized).apply()
        _state.update {
            it.copy(
                enteredCode = normalized,
                statusText = if (normalized.length == 4) {
                    "이 4자리 코드를 Mac 앱에 입력한 뒤 페어링을 저장하세요."
                } else {
                    "4자리 코드를 모두 입력하세요"
                }
            )
        }
    }

    fun regeneratePairingCode() {
        val code = generateAndPersistPairingCode()
        _state.update {
            it.copy(
                enteredCode = code,
                statusText = "새 코드가 생성됐습니다. 이 4자리 코드를 Mac 앱에 입력하세요."
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
        val nextPairingCode = generateAndPersistPairingCode()
        _state.update {
            it.copy(
                enteredCode = nextPairingCode,
                statusText = "$deviceName 신뢰 기기를 저장했습니다. 다음 페어링용 새 코드를 준비했습니다.",
                trustedPeerCount = peers.size,
                lastTrustedPeerName = deviceName
            )
        }
    }

    fun markPeerSeen(deviceName: String, trusted: Boolean) {
        _state.update {
            it.copy(
                statusText = if (trusted) {
                    "$deviceName 신뢰 연결 활성화됨"
                } else {
                    "연결된 Mac은 4자리 페어링이 필요합니다"
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

    private fun generateAndPersistPairingCode(): String {
        val code = Random.nextInt(0, 10_000).toString().padStart(4, '0')
        prefs().edit().putString(keyEnteredCode, code).apply()
        return code
    }

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
