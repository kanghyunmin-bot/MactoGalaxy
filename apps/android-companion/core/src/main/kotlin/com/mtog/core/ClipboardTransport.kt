package com.mtog.core

sealed class ClipboardAuthorityStatus {
    data object Available : ClipboardAuthorityStatus()
    data class Blocked(val reason: String) : ClipboardAuthorityStatus()
    data object Stopped : ClipboardAuthorityStatus()
    data class Failed(val reason: String) : ClipboardAuthorityStatus()
}

interface ClipboardTextStore {
    var changeHandler: ((AutomaticClipboardKind, String) -> Unit)?
    fun write(kind: AutomaticClipboardKind, content: String)
}

interface ClipboardEventTransport {
    var status: ClipboardAuthorityStatus
    var receiveHandler: ((ClipboardEvent) -> Unit)?
    fun send(event: ClipboardEvent)
    fun stop()
}

class AutomaticClipboardCoordinator(
    private val store: ClipboardTextStore,
    private val transport: ClipboardEventTransport,
    sourceID: String,
    sessionID: String
) {
    var status: ClipboardAuthorityStatus = ClipboardAuthorityStatus.Stopped
        private set
    private val engine = ClipboardSyncEngine(sourceID, sessionID)
    private var applyingRemote = false

    fun start(sessionID: String): ClipboardAuthorityStatus {
        engine.begin(sessionID)
        status = transport.status
        if (status != ClipboardAuthorityStatus.Available) return status
        store.changeHandler = { kind, content ->
            if (!applyingRemote) {
                try {
                    transport.send(engine.makeLocalEvent(kind, content))
                } catch (error: ClipboardEventException) {
                    status = ClipboardAuthorityStatus.Failed(error::class.simpleName.orEmpty())
                }
            }
        }
        transport.receiveHandler = { event ->
            val result = engine.receive(event)
            if (result is ClipboardReceiveResult.Accepted) {
                applyingRemote = true
                store.write(event.kind, result.content)
                applyingRemote = false
            }
        }
        return status
    }

    fun stop() {
        store.changeHandler = null
        transport.receiveHandler = null
        transport.stop()
        status = ClipboardAuthorityStatus.Stopped
    }
}

class InMemoryClipboardStore : ClipboardTextStore {
    override var changeHandler: ((AutomaticClipboardKind, String) -> Unit)? = null
    var kind: AutomaticClipboardKind? = null
        private set
    var content: String? = null
        private set

    override fun write(kind: AutomaticClipboardKind, content: String) {
        this.kind = kind
        this.content = content
        changeHandler?.invoke(kind, content)
    }

    fun simulateLocalCopy(kind: AutomaticClipboardKind, content: String) = write(kind, content)
}

class InMemoryClipboardTransport(
    override var status: ClipboardAuthorityStatus = ClipboardAuthorityStatus.Available
) : ClipboardEventTransport {
    override var receiveHandler: ((ClipboardEvent) -> Unit)? = null
    var peer: InMemoryClipboardTransport? = null

    override fun send(event: ClipboardEvent) {
        if (status == ClipboardAuthorityStatus.Available) peer?.receiveHandler?.invoke(event)
    }

    override fun stop() {
        status = ClipboardAuthorityStatus.Stopped
    }
}
