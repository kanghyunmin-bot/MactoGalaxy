package com.mtog.app.transport

class UsbDirectTransportAdapter {
    enum class Mode {
        AdbMvp,
        AoaCandidate
    }

    var mode: Mode = Mode.AdbMvp

    fun start() {
        // Placeholder for ADB loopback bootstrap or future AOA endpoint bootstrap.
    }

    fun stop() {
    }
}
