package com.mtog.app.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.mtog.app.session.SessionRuntime
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.UUID

data class ClipboardTransferPayload(
    val kind: String,
    val text: String? = null,
    val name: String? = null,
    val mimeType: String? = null,
    val dataBase64: String? = null,
    val sizeBytes: Int,
    val sourceId: String? = null
) {
    companion object {
        const val protocolVersion = "1"
    }

    val previewTitle: String
        get() = when (kind.lowercase()) {
            "text", "url" -> text.orEmpty().trim().take(48).ifEmpty { "클립보드 항목" }
            else -> name?.takeIf { it.isNotBlank() } ?: "클립보드 항목"
        }

    val signature: String
        get() = when (kind.lowercase()) {
            "text", "url" -> "${kind.lowercase()}|${text.orEmpty()}"
            else -> listOf(
                kind.lowercase(),
                name.orEmpty(),
                mimeType.orEmpty(),
                sizeBytes.toString(),
                dataBase64.orEmpty().take(128)
            ).joinToString("|")
        }

    fun toWirePayload(): Map<String, String> {
        val payload = linkedMapOf(
            "protocolVersion" to protocolVersion,
            "kind" to kind,
            "sizeBytes" to sizeBytes.toString(),
            "itemId" to UUID.randomUUID().toString(),
            "createdAtUnixMs" to System.currentTimeMillis().toString(),
            "sha256" to contentHash()
        )
        sourceId?.takeIf { it.isNotEmpty() }?.let { payload["sourceId"] = it }
        text?.takeIf { it.isNotEmpty() }?.let { payload["text"] = it }
        name?.takeIf { it.isNotEmpty() }?.let { payload["name"] = it }
        mimeType?.takeIf { it.isNotEmpty() }?.let { payload["mimeType"] = it }
        dataBase64?.takeIf { it.isNotEmpty() }?.let { payload["dataBase64"] = it }
        return payload
    }

    private fun contentHash(): String {
        val bytes = when (kind.lowercase()) {
            "text", "url" -> text.orEmpty().toByteArray(Charsets.UTF_8)
            else -> runCatching {
                android.util.Base64.decode(dataBase64.orEmpty(), android.util.Base64.DEFAULT)
            }.getOrNull() ?: ByteArray(0)
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }
}

class ClipboardSyncManager(
    context: Context
) {
    companion object {
        private const val maxTransferBytes = 24 * 1_024 * 1_024
        private const val maxTextBytes = 256 * 1_024
        private const val maxCacheBytes = 160 * 1_024 * 1_024
        private const val maxCacheFiles = 80
        private const val maxCacheAgeMs = 7L * 24L * 60L * 60L * 1000L
    }

    private val appContext = context.applicationContext
    private val clipboardManager = appContext.getSystemService(ClipboardManager::class.java)
    private val contentResolver = appContext.contentResolver
    private val sharedDirectory = File(appContext.cacheDir, "clipboard").apply {
        mkdirs()
    }
    private val localSourceId: String by lazy { loadOrCreateSourceId() }

    private var started = false
    private var listenerAttached = false
    private var suppressedLocalChangeCount = 0
    private var lastObservedSignature: String? = null
    private var localPayloadHandler: ((ClipboardTransferPayload) -> Unit)? = null

    private val listener = ClipboardManager.OnPrimaryClipChangedListener {
        handlePrimaryClipChanged()
    }

    fun start(localPayloadHandler: (ClipboardTransferPayload) -> Unit) {
        if (started) {
            return
        }

        this.localPayloadHandler = localPayloadHandler
        cleanupSharedDirectory()
        lastObservedSignature = safeReadPrimaryClipPayload()?.signature
        started = true
        SessionRuntime.markClipboardEvent("수동 클립보드 동기화 준비 완료")
    }

    fun stop() {
        if (!started) {
            return
        }

        if (listenerAttached) {
            clipboardManager.removePrimaryClipChangedListener(listener)
            listenerAttached = false
        }
        localPayloadHandler = null
        suppressedLocalChangeCount = 0
        started = false
        SessionRuntime.markClipboardEvent("수동 클립보드 동기화가 중지되었습니다")
    }

    fun currentPayload(): ClipboardTransferPayload? {
        return safeReadPrimaryClipPayload()
    }

    fun recordManualLocalPayload(payload: ClipboardTransferPayload) {
        recordLocalPayload(payload, detailSuffix = "갤럭시 클립보드에서 수동 동기화")
    }

    fun applyRemotePayload(
        payload: Map<String, String>,
        sourceName: String,
        recordHistory: Boolean = true
    ) {
        if (payload["sourceId"] == localSourceId) {
            SessionRuntime.markClipboardEvent("내가 보낸 클립보드 응답은 무시했습니다")
            return
        }
        if (payload["protocolVersion"]?.takeIf { it.isNotBlank() } != null &&
            payload["protocolVersion"] != ClipboardTransferPayload.protocolVersion
        ) {
            SessionRuntime.markClipboardEvent("지원하지 않는 클립보드 프로토콜입니다")
            return
        }

        val kind = payload["kind"]?.lowercase().orEmpty()
        when (kind) {
            "text", "url" -> {
                val text = payload["text"].orEmpty()
                val textSize = text.toByteArray(Charsets.UTF_8).size
                if (text.isEmpty() || textSize > maxTextBytes) {
                    SessionRuntime.markClipboardEvent("Mac 텍스트 클립보드를 거절했습니다: 비어 있거나 너무 큽니다")
                    return
                }
                if (!matchesHash(payload["sha256"], text.toByteArray(Charsets.UTF_8))) {
                    SessionRuntime.markClipboardEvent("Mac 텍스트 클립보드를 거절했습니다: 무결성 확인 실패")
                    return
                }
                suppressLocalChanges()
                clipboardManager.setPrimaryClip(ClipData.newPlainText("MtoG Remote", text))
                lastObservedSignature = ClipboardTransferPayload(
                    kind = kind,
                    text = text,
                    mimeType = "text/plain",
                    sizeBytes = textSize,
                    sourceId = localSourceId
                ).signature
                if (recordHistory) {
                    ClipboardHistoryStore.recordPayload(
                        context = appContext,
                        payload = ClipboardTransferPayload(
                            kind = kind,
                            text = text,
                            mimeType = "text/plain",
                            sizeBytes = textSize,
                            sourceId = localSourceId
                        ),
                        detail = "$sourceName 에서 받음"
                    )
                }
                SessionRuntime.markClipboardEvent("$sourceName 의 $kind 클립보드를 적용했습니다")
            }

            "image", "video", "file" -> {
                val encoded = payload["dataBase64"] ?: run {
                    SessionRuntime.markClipboardEvent("Mac $kind 클립보드를 거절했습니다: 데이터가 없습니다")
                    return
                }
                if (encoded.length > maxBase64Characters(maxTransferBytes)) {
                    SessionRuntime.markClipboardEvent("Mac $kind 클립보드를 거절했습니다: 데이터가 너무 큽니다")
                    return
                }
                val bytes = runCatching { android.util.Base64.decode(encoded, android.util.Base64.DEFAULT) }
                    .getOrNull() ?: run {
                    SessionRuntime.markClipboardEvent("Mac $kind 클립보드를 거절했습니다: 데이터 형식이 올바르지 않습니다")
                    return
                }
                if (bytes.isEmpty() || bytes.size > maxTransferBytes) {
                    SessionRuntime.markClipboardEvent("Mac $kind 클립보드를 거절했습니다: 비어 있거나 너무 큽니다")
                    return
                }
                if (!matchesHash(payload["sha256"], bytes)) {
                    SessionRuntime.markClipboardEvent("Mac $kind 클립보드를 거절했습니다: 무결성 확인 실패")
                    return
                }
                val mimeType = payload["mimeType"].orEmpty().ifEmpty { "application/octet-stream" }
                val file = writeSharedFile(
                    name = payload["name"],
                    mimeType = mimeType,
                    data = bytes
                )
                val uri = FileProvider.getUriForFile(
                    appContext,
                    "${appContext.packageName}.fileprovider",
                    file
                )
                val label = payload["name"] ?: "MtoG Remote"
                val clip = ClipData(
                    ClipDescription(label, arrayOf(mimeType)),
                    ClipData.Item(uri)
                )
                suppressLocalChanges()
                clipboardManager.setPrimaryClip(clip)
                val transferPayload = ClipboardTransferPayload(
                    kind = kind,
                    name = payload["name"],
                    mimeType = mimeType,
                    dataBase64 = encoded,
                    sizeBytes = bytes.size,
                    sourceId = localSourceId
                )
                lastObservedSignature = transferPayload.signature
                if (recordHistory) {
                    ClipboardHistoryStore.recordPayload(
                        context = appContext,
                        payload = transferPayload,
                        detail = "$mimeType · $sourceName 에서 받음"
                    )
                }
                cleanupSharedDirectory()
                SessionRuntime.markClipboardEvent("$sourceName 의 $kind 클립보드를 적용했습니다")
            }

            else -> {
                SessionRuntime.markClipboardEvent("지원하지 않는 클립보드 형식입니다: ${kind.ifBlank { "알 수 없음" }}")
            }
        }
    }

    fun withTemporaryPlainText(text: String, operation: () -> Boolean): Boolean {
        val textSize = text.toByteArray(Charsets.UTF_8).size
        if (text.isEmpty() || textSize > maxTextBytes) {
            return false
        }

        val previousClip = clipboardManager.primaryClip
        val previousSignature = lastObservedSignature
        suppressLocalChanges(if (previousClip != null) 2 else 1)
        clipboardManager.setPrimaryClip(ClipData.newPlainText("MtoG Keyboard", text))

        return try {
            operation()
        } finally {
            if (previousClip != null) {
                clipboardManager.setPrimaryClip(previousClip)
            } else {
                clipboardManager.clearPrimaryClip()
            }
            lastObservedSignature = previousSignature
        }
    }

    private fun handlePrimaryClipChanged() {
        if (suppressedLocalChangeCount > 0) {
            suppressedLocalChangeCount -= 1
            lastObservedSignature = safeReadPrimaryClipPayload()?.signature
            SessionRuntime.markClipboardEvent("앱이 적용한 클립보드 반영은 무시했습니다")
            return
        }

        val payload = safeReadPrimaryClipPayload() ?: run {
            SessionRuntime.markClipboardEvent("갤럭시 클립보드가 비어 있거나, 지원하지 않거나, Android 정책으로 차단되었습니다")
            return
        }
        if (payload.signature == lastObservedSignature) {
            return
        }
        lastObservedSignature = payload.signature

        recordLocalPayload(payload, detailSuffix = "갤럭시 클립보드에서 받음")
        localPayloadHandler?.invoke(payload)
        SessionRuntime.markClipboardEvent("갤럭시 ${payload.kind} 클립보드 변경을 감지했습니다")
    }

    private fun recordLocalPayload(payload: ClipboardTransferPayload, detailSuffix: String) {
        ClipboardHistoryStore.recordPayload(
            context = appContext,
            payload = payload,
            detail = when (payload.kind.lowercase()) {
                "image", "video", "file" -> "${payload.mimeType ?: "application/octet-stream"} · $detailSuffix"
                else -> detailSuffix
            }
        )
    }

    private fun safeReadPrimaryClipPayload(): ClipboardTransferPayload? {
        return runCatching {
            readPrimaryClipPayload()
        }.onFailure { error ->
            SessionRuntime.markClipboardEvent(
                "갤럭시 클립보드를 읽지 못했습니다: ${error.localizedMessage ?: error.javaClass.simpleName}"
            )
        }.getOrNull()
    }

    private fun readPrimaryClipPayload(): ClipboardTransferPayload? {
        val primaryClip = clipboardManager.primaryClip ?: return null
        if (primaryClip.itemCount <= 0) {
            return null
        }

        val item = primaryClip.getItemAt(0)
        return when {
            item.uri != null -> buildBinaryPayload(item.uri)
            else -> {
                val rawText = item.coerceToText(appContext)?.toString().orEmpty()
                val sizeBytes = rawText.toByteArray(Charsets.UTF_8).size
                if (rawText.isEmpty() || sizeBytes > maxTextBytes) {
                    null
                } else {
                    val normalized = rawText.trim()
                    val kind = if (normalized.startsWith("http://") || normalized.startsWith("https://")) "url" else "text"
                    ClipboardTransferPayload(
                        kind = kind,
                        text = rawText,
                        mimeType = "text/plain",
                        sizeBytes = sizeBytes,
                        sourceId = localSourceId
                    )
                }
            }
        }
    }

    private fun buildBinaryPayload(uri: Uri): ClipboardTransferPayload? {
        val knownSize = querySizeBytes(uri)
        if (knownSize != null && knownSize > maxTransferBytes) {
            SessionRuntime.markClipboardEvent("갤럭시 클립보드 항목이 24MB를 초과합니다")
            return null
        }
        val mimeType = runCatching {
            contentResolver.getType(uri)
        }.getOrNull().orEmpty().ifEmpty {
            inferMimeTypeFromUri(uri)
        }
        val input = runCatching {
            contentResolver.openInputStream(uri)
        }.onFailure { error ->
            SessionRuntime.markClipboardEvent(
                "갤럭시 클립보드 파일 권한이 없어 읽지 못했습니다: ${error.localizedMessage ?: error.javaClass.simpleName}"
            )
        }.getOrNull() ?: return null
        val bytes = input.use { stream -> readBytesLimited(stream, maxTransferBytes) } ?: return null
        if (bytes.isEmpty() || bytes.size > maxTransferBytes) {
            SessionRuntime.markClipboardEvent("갤럭시 클립보드 파일이 비어 있거나 너무 큽니다")
            return null
        }

        val kind = when {
            mimeType.startsWith("image/") -> "image"
            mimeType.startsWith("video/") -> "video"
            else -> "file"
        }

        return ClipboardTransferPayload(
            kind = kind,
            name = sanitizeName(displayNameForUri(uri), mimeType),
            mimeType = mimeType.ifEmpty { "application/octet-stream" },
            dataBase64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP),
            sizeBytes = bytes.size,
            sourceId = localSourceId
        )
    }

    private fun displayNameForUri(uri: Uri): String {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        val resolved = runCatching {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) {
                    cursor.getString(index)
                } else {
                    null
                }
            }
        }.getOrNull()

        return resolved?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "clipboard-item"
    }

    private fun querySizeBytes(uri: Uri): Int? {
        val fromCursor = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (index >= 0 && cursor.moveToFirst() && !cursor.isNull(index)) {
                    cursor.getLong(index)
                } else {
                    null
                }
            }
        }.getOrNull()

        val resolved = fromCursor ?: runCatching {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                descriptor.length.takeIf { it >= 0 }
            }
        }.getOrNull()

        return resolved
            ?.takeIf { it in 0..Int.MAX_VALUE.toLong() }
            ?.toInt()
    }

    private fun readBytesLimited(input: java.io.InputStream, maxBytes: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var totalRead = 0

        while (true) {
            val count = input.read(buffer)
            if (count <= 0) {
                break
            }
            totalRead += count
            if (totalRead > maxBytes) {
                return null
            }
            output.write(buffer, 0, count)
        }

        return output.toByteArray()
    }

    private fun inferMimeTypeFromUri(uri: Uri): String {
        val extension = MimeTypeMap.getFileExtensionFromUrl(uri.toString()).lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private fun writeSharedFile(name: String?, mimeType: String, data: ByteArray): File {
        val fileName = sanitizeName(name, mimeType)
        val file = File(sharedDirectory, "${UUID.randomUUID()}-$fileName")
        file.writeBytes(data)
        cleanupSharedDirectory()
        return file
    }

    private fun sanitizeName(name: String?, mimeType: String): String {
        val safeName = name
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.replace(Regex("""[\\/:\?%\*\|"<>\\p{Cntrl}]"""), "-")
            ?.take(96)
        if (safeName != null) {
            return safeName
        }

        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType)
            ?.ifEmpty { null }
        val baseName = when {
            mimeType.startsWith("image/") -> "clipboard-image"
            mimeType.startsWith("video/") -> "clipboard-video"
            else -> "clipboard-file"
        }
        return if (extension != null) "$baseName.$extension" else "$baseName.bin"
    }

    private fun suppressLocalChanges(count: Int = 1) {
        if (count > 0) {
            suppressedLocalChangeCount += count
        }
    }

    private fun loadOrCreateSourceId(): String {
        val prefs = appContext.getSharedPreferences("mtog.clipboard", Context.MODE_PRIVATE)
        val existing = prefs.getString("source_id", null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val generated = UUID.randomUUID().toString()
        prefs.edit().putString("source_id", generated).apply()
        return generated
    }

    private fun matchesHash(expected: String?, bytes: ByteArray): Boolean {
        if (expected.isNullOrBlank()) {
            return true
        }
        val actual = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
        return expected.equals(actual, ignoreCase = true)
    }

    private fun maxBase64Characters(bytes: Int): Int {
        return ((bytes + 2) / 3) * 4 + 128
    }

    private fun cleanupSharedDirectory() {
        val files = sharedDirectory
            .listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            ?: return

        val now = System.currentTimeMillis()
        files
            .filter { now - it.lastModified() > maxCacheAgeMs }
            .forEach { it.delete() }

        var totalBytes = 0L
        sharedDirectory
            .listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            ?.forEachIndexed { index, file ->
                totalBytes += file.length()
                if (index >= maxCacheFiles || totalBytes > maxCacheBytes) {
                    file.delete()
                }
            }
    }
}
