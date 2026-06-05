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
        label = "USB 연결 대기",
        detail = "케이블은 물리 연결입니다. 앱 연결에는 USB 개발 모드 또는 검증된 USB HID 방식이 필요합니다."
    ),
    UsbAdbMvp(
        label = "USB 개발 모드",
        detail = "현재 가장 빠르게 확인 가능한 연결 방식입니다. Android USB 디버깅이 필요합니다."
    ),
    UsbAoaCandidate(
        label = "USB HID 후보",
        detail = "제품용 USB 입력 목표 방식입니다. 실제 Galaxy Tab S11에서 검증이 필요합니다."
    ),
    SecureLanCandidate(
        label = "개인 Wi-Fi 연결",
        detail = "개인 Wi-Fi 또는 핫스팟에서 사용하는 무선 연결입니다. 페어링된 기기만 연결해야 합니다."
    )
}
