package com.mtog.app.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.mtog.app.session.SessionRuntime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.text.DateFormat
import java.util.Date
import java.util.UUID

data class ClipboardHistoryRecord(
    val id: String = UUID.randomUUID().toString(),
    val kind: String,
    val kindBadge: String,
    val title: String,
    val detail: String,
    val timestamp: String,
    val size: String,
    val text: String? = null,
    val mimeType: String? = null,
    val fileName: String? = null,
    val filePath: String? = null
) {
    val canReCopy: Boolean
        get() = !text.isNullOrEmpty() || filePath?.let { File(it).isFile } == true
}

object ClipboardHistoryStore {
    private const val prefsName = "mtog.clipboard"
    private const val keyHistory = "history_items"
    private const val maxItems = 50

    private val _history = MutableStateFlow<List<ClipboardHistoryRecord>>(emptyList())
    val history: StateFlow<List<ClipboardHistoryRecord>> = _history

    private var appContext: Context? = null
    private var initialized = false

    fun initialize(context: Context) {
        if (initialized) {
            return
        }

        appContext = context.applicationContext
        _history.value = loadHistory() ?: emptyList()
        initialized = true
    }

    fun record(
        kind: String,
        title: String,
        detail: String,
        sizeBytes: Int,
        text: String? = null,
        mimeType: String? = null,
        fileName: String? = null,
        filePath: String? = null
    ) {
        val normalizedKind = kind.lowercase()
        val next = ClipboardHistoryRecord(
            kind = normalizedKind,
            kindBadge = badgeFor(normalizedKind),
            title = title.ifBlank { "클립보드 항목" }.take(96),
            detail = detail.take(140),
            timestamp = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date()),
            size = humanSize(sizeBytes),
            text = text,
            mimeType = mimeType,
            fileName = fileName,
            filePath = filePath
        )

        val deduplicated = _history.value.filterNot {
            it.kind == next.kind &&
                it.title == next.title &&
                it.detail == next.detail &&
                it.size == next.size
        }
        _history.value = listOf(next) + deduplicated.take(maxItems - 1)
        persist()
    }

    fun recordPayload(context: Context, payload: ClipboardTransferPayload, detail: String) {
        initialize(context)
        val kind = payload.kind.lowercase()
        val filePath = if (kind == "image" || kind == "video" || kind == "file") {
            val bytes = runCatching {
                android.util.Base64.decode(payload.dataBase64.orEmpty(), android.util.Base64.DEFAULT)
            }.getOrNull()
            bytes?.takeIf { it.isNotEmpty() }?.let {
                writeHistoryFile(context, payload.name, payload.mimeType, it)
            }
        } else {
            null
        }

        record(
            kind = kind,
            title = payload.previewTitle,
            detail = detail,
            sizeBytes = payload.sizeBytes,
            text = if (kind == "text" || kind == "url") payload.text else null,
            mimeType = payload.mimeType,
            fileName = payload.name,
            filePath = filePath
        )
    }

    fun recopy(context: Context, item: ClipboardHistoryRecord): Boolean {
        initialize(context)
        val clipboard = context.getSystemService(ClipboardManager::class.java)

        if (item.kind == "text" || item.kind == "url") {
            val text = item.text?.takeIf { it.isNotEmpty() } ?: return false
            clipboard.setPrimaryClip(ClipData.newPlainText("MtoG History", text))
            SessionRuntime.markClipboardEvent("${kindLabel(item.kind)} 기록을 다시 복사했습니다")
            return true
        }

        val file = item.filePath?.let { File(it) }?.takeIf { it.isFile } ?: return false
        val mimeType = item.mimeType?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )
        val clip = ClipData(
            ClipDescription(item.fileName ?: item.title, arrayOf(mimeType)),
            ClipData.Item(uri)
        )
        clipboard.setPrimaryClip(clip)
        SessionRuntime.markClipboardEvent("${kindLabel(item.kind)} 기록을 다시 복사했습니다")
        return true
    }

    fun download(context: Context, item: ClipboardHistoryRecord): Boolean {
        initialize(context)
        val bytes = if (item.kind == "text" || item.kind == "url") {
            item.text?.takeIf { it.isNotEmpty() }?.toByteArray(Charsets.UTF_8)
        } else {
            item.filePath?.let { path ->
                runCatching { File(path).takeIf { it.isFile }?.readBytes() }.getOrNull()
            }
        } ?: return false

        val mimeType = when {
            item.kind == "text" || item.kind == "url" -> "text/plain"
            !item.mimeType.isNullOrBlank() -> item.mimeType
            else -> "application/octet-stream"
        }
        val fileName = sanitizeName(
            item.fileName
                ?: if (item.kind == "text" || item.kind == "url") "clipboard-text.txt" else item.title,
            mimeType
        )
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/MtoG Clipboard")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
        return runCatching {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("저장 경로를 열 수 없습니다")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            SessionRuntime.markClipboardEvent("기록 항목을 다운로드/MtoG Clipboard 폴더에 저장했습니다")
            true
        }.getOrElse {
            runCatching { resolver.delete(uri, null, null) }
            false
        }
    }

    private fun persist() {
        val context = appContext ?: return
        val array = JSONArray()
        _history.value.forEach { item ->
            array.put(
                JSONObject()
                    .put("id", item.id)
                    .put("kind", item.kind)
                    .put("kindBadge", item.kindBadge)
                    .put("title", item.title)
                    .put("detail", item.detail)
                    .put("timestamp", item.timestamp)
                    .put("size", item.size)
                    .putNullable("text", item.text)
                    .putNullable("mimeType", item.mimeType)
                    .putNullable("fileName", item.fileName)
                    .putNullable("filePath", item.filePath)
            )
        }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(keyHistory, array.toString())
            .apply()
    }

    private fun loadHistory(): List<ClipboardHistoryRecord>? {
        val context = appContext ?: return null
        val encoded = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(keyHistory, null) ?: return null

        return runCatching {
            val array = JSONArray(encoded)
            buildList {
                repeat(array.length()) { index ->
                    val item = array.getJSONObject(index)
                    val kind = item.optString("kind").ifBlank {
                        kindFromBadge(item.optString("kindBadge", "TXT"))
                    }
                    add(
                        ClipboardHistoryRecord(
                            id = item.optString("id", UUID.randomUUID().toString()),
                            kind = kind,
                            kindBadge = item.optString("kindBadge", badgeFor(kind)),
                            title = item.optString("title", "클립보드 항목"),
                            detail = item.optString("detail", ""),
                            timestamp = item.optString("timestamp", ""),
                            size = item.optString("size", ""),
                            text = item.optNullableString("text"),
                            mimeType = item.optNullableString("mimeType"),
                            fileName = item.optNullableString("fileName"),
                            filePath = item.optNullableString("filePath")
                        )
                    )
                }
            }
        }.getOrNull()
    }

    private fun writeHistoryFile(
        context: Context,
        name: String?,
        mimeType: String?,
        bytes: ByteArray
    ): String? {
        val directory = File(context.cacheDir, "clipboard/history").apply { mkdirs() }
        val safeName = sanitizeName(name, mimeType ?: "application/octet-stream")
        val file = File(directory, "${UUID.randomUUID()}-$safeName")
        return runCatching {
            file.writeBytes(bytes)
            file.absolutePath
        }.getOrNull()
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

    private fun badgeFor(kind: String): String {
        return when (kind.lowercase()) {
            "url" -> "URL"
            "image" -> "IMG"
            "video" -> "VID"
            "file" -> "FILE"
            else -> "TXT"
        }
    }

    private fun kindFromBadge(badge: String): String {
        return when (badge.uppercase()) {
            "URL" -> "url"
            "IMG" -> "image"
            "VID" -> "video"
            "FILE" -> "file"
            else -> "text"
        }
    }

    private fun kindLabel(kind: String): String {
        return when (kind.lowercase()) {
            "url" -> "URL"
            "image" -> "이미지"
            "video" -> "영상"
            "file" -> "파일"
            else -> "텍스트"
        }
    }

    private fun humanSize(sizeBytes: Int): String {
        return when {
            sizeBytes >= 1_000_000 -> String.format(Locale.US, "%.1f MB", sizeBytes / 1_000_000.0)
            sizeBytes >= 1_000 -> String.format(Locale.US, "%.1f KB", sizeBytes / 1_000.0)
            else -> "$sizeBytes B"
        }
    }

    private fun JSONObject.putNullable(key: String, value: String?): JSONObject {
        if (value == null) {
            put(key, JSONObject.NULL)
        } else {
            put(key, value)
        }
        return this
    }

    private fun JSONObject.optNullableString(key: String): String? {
        if (!has(key) || isNull(key)) {
            return null
        }
        return optString(key).takeIf { it.isNotEmpty() }
    }
}
