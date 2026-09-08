package com.mtog.core

import java.security.MessageDigest

enum class AutomaticClipboardKind { Text, Url }

sealed class ClipboardEventException : Exception() {
    data object EmptyContent : ClipboardEventException()
    data object ContentTooLarge : ClipboardEventException()
    data object InvalidIdentity : ClipboardEventException()
}

data class ClipboardEvent(
    val sourceID: String,
    val sessionID: String,
    val sequence: Long,
    val kind: AutomaticClipboardKind,
    val contentHash: String,
    val content: String
) {
    companion object {
        fun make(
            sourceID: String,
            sessionID: String,
            sequence: Long,
            kind: AutomaticClipboardKind,
            content: String
        ): ClipboardEvent {
            if (sourceID.isBlank() || sessionID.isBlank() || sequence <= 0) {
                throw ClipboardEventException.InvalidIdentity
            }
            if (content.isEmpty()) throw ClipboardEventException.EmptyContent
            if (content.toByteArray(Charsets.UTF_8).size > ProtocolLimits.AUTOMATIC_CLIPBOARD_BYTES) {
                throw ClipboardEventException.ContentTooLarge
            }
            return ClipboardEvent(sourceID, sessionID, sequence, kind, hash(content), content)
        }

        fun hash(content: String): String = MessageDigest.getInstance("SHA-256")
            .digest(content.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }
}
