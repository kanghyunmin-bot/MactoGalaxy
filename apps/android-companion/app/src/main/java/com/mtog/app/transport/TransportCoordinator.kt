package com.mtog.app.transport

class TransportCoordinator {
    var mode: TransportMode = TransportMode.UsbAdbMvp
        private set

    val udpAdapter = UdpTransportAdapter()
    val usbAdapter = UsbDirectTransportAdapter()

    fun rotateMode(): TransportMode {
        mode = when (mode) {
            TransportMode.UsbPending -> TransportMode.UsbAdbMvp
            TransportMode.UsbAdbMvp -> TransportMode.UsbAoaCandidate
            TransportMode.UsbAoaCandidate -> TransportMode.SecureLanCandidate
            TransportMode.SecureLanCandidate -> TransportMode.UsbPending
        }
        return mode
    }
}

enum class TransportMode(val label: String, val detail: String) {
    UsbPending(
        label = "USB Direct Pending",
        detail = "Cable is the physical path. Direct app transport still needs ADB MVP or validated AOA."
    ),
    UsbAdbMvp(
        label = "USB ADB MVP",
        detail = "Current fastest implementation path. Requires Android USB debugging."
    ),
    UsbAoaCandidate(
        label = "USB AOA Candidate",
        detail = "Production USB target. Needs real Galaxy Tab S11 validation."
    ),
    SecureLanCandidate(
        label = "Secure LAN Candidate",
        detail = "Private-network fallback target. Use only with paired-device authentication and encrypted app sessions."
    )
}
