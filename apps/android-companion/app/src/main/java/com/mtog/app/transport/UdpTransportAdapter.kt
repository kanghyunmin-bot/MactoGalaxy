package com.mtog.app.transport

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class UdpTransportAdapter {
    private var socket: DatagramSocket? = null

    fun open(port: Int) {
        // Experimental only. UDP is valid only when Android and macOS already share an IP path.
        // It must not be presented as "Thunderbolt direct" and must be wrapped by authenticated encryption.
        if (socket == null) {
            socket = DatagramSocket(port)
        }
    }

    fun close() {
        socket?.close()
        socket = null
    }

    fun send(host: String, port: Int, payload: ByteArray) {
        val datagram = DatagramPacket(payload, payload.size, InetAddress.getByName(host), port)
        socket?.send(datagram)
    }
}
