package com.mtog.core

object ProtocolLimits {
    const val VERSION = 2
    const val CONTROL_PAYLOAD_BYTES = 36 * 1024 * 1024
    const val VIDEO_PAYLOAD_BYTES = 8 * 1024 * 1024
    const val VIDEO_CONFIG_BYTES = 256 * 1024
    const val VIDEO_CONTROL_BYTES = 64 * 1024
    const val MAXIMUM_VIDEO_DIMENSION = 8_192
    const val AUTOMATIC_CLIPBOARD_BYTES = 256 * 1024
}
