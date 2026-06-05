package com.mtog.app.transport

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.mtog.app.session.SessionRuntime

class WirelessServiceAdvertiser(context: Context) {
    companion object {
        const val serviceType = "_mtog._tcp."
    }

    private val appContext = context.applicationContext
    private val nsdManager: NsdManager? = appContext.getSystemService(NsdManager::class.java)
    private var registrationListener: NsdManager.RegistrationListener? = null

    fun start(port: Int, deviceName: String, deviceId: String) {
        val manager = nsdManager ?: run {
            SessionRuntime.markDiscovery("이 기기에서는 Wi-Fi 검색 등록을 사용할 수 없습니다")
            return
        }
        if (registrationListener != null) {
            SessionRuntime.markDiscovery("이미 Wi-Fi 검색에 표시 중입니다")
            return
        }

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = serviceNameFor(deviceName)
            serviceType = Companion.serviceType
            setPort(port)
            setAttribute("app", "MtoG")
            setAttribute("version", "1")
            setAttribute("role", "android-companion")
            setAttribute("device", deviceName.take(64))
            setAttribute("deviceId", deviceId.take(64))
            setAttribute("pairing", "required")
        }

        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(registeredInfo: NsdServiceInfo) {
                SessionRuntime.markDiscovery("${registeredInfo.serviceName} 으로 Wi-Fi 검색에 표시 중")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                registrationListener = null
                SessionRuntime.markDiscovery("Wi-Fi 검색 등록 실패: $errorCode")
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                SessionRuntime.markDiscovery("Wi-Fi 검색 표시가 중지되었습니다")
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                SessionRuntime.markDiscovery("Wi-Fi 검색 표시 중지 실패: $errorCode")
            }
        }

        registrationListener = listener
        runCatching {
            manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
        }.onFailure { error ->
            registrationListener = null
            SessionRuntime.markDiscovery("Wi-Fi 검색 등록 실패: ${error.message ?: "알 수 없음"}")
        }
    }

    fun stop() {
        val listener = registrationListener ?: return
        registrationListener = null
        runCatching {
            nsdManager?.unregisterService(listener)
        }.onFailure { error ->
            SessionRuntime.markDiscovery("Wi-Fi 검색 표시 중지 실패: ${error.message ?: "알 수 없음"}")
        }
    }

    private fun serviceNameFor(deviceName: String): String {
        val cleaned = deviceName
            .replace(Regex("[^A-Za-z0-9 _.-]"), "")
            .trim()
            .ifBlank { "Galaxy Tab" }
            .take(36)
        return "MtoG $cleaned"
    }
}
