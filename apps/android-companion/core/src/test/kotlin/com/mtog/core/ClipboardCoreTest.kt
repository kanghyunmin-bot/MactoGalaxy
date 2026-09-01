package com.mtog.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ClipboardCoreTest {
    @Test
    fun fakeStoreAndTransportCoverBidirectionalEdges() {
        val macStore = InMemoryClipboardStore()
        val galaxyStore = InMemoryClipboardStore()
        val macTransport = InMemoryClipboardTransport()
        val galaxyTransport = InMemoryClipboardTransport()
        macTransport.peer = galaxyTransport
        galaxyTransport.peer = macTransport
        val mac = AutomaticClipboardCoordinator(macStore, macTransport, "mac", "session-1")
        val galaxy = AutomaticClipboardCoordinator(galaxyStore, galaxyTransport, "galaxy", "session-1")
        assertEquals(ClipboardAuthorityStatus.Available, mac.start("session-1"))
        assertEquals(ClipboardAuthorityStatus.Available, galaxy.start("session-1"))
        macStore.simulateLocalCopy(AutomaticClipboardKind.Text, "한글과 emoji 😀")
        assertEquals("한글과 emoji 😀", galaxyStore.content)
        galaxyStore.simulateLocalCopy(AutomaticClipboardKind.Url, "https://example.test/path")
        assertEquals("https://example.test/path", macStore.content)
        repeat(20) { macStore.simulateLocalCopy(AutomaticClipboardKind.Text, "rapid-$it") }
        assertEquals("rapid-19", galaxyStore.content)

        val stale = ClipboardEvent.make("mac", "session-1", 22, AutomaticClipboardKind.Text, "stale")
        mac.start("session-2")
        galaxy.start("session-2")
        macTransport.send(stale)
        assertEquals("rapid-19", galaxyStore.content)
        val bad = ClipboardEvent("mac", "session-2", 1, AutomaticClipboardKind.Text, "0".repeat(64), "bad")
        macTransport.send(bad)
        assertEquals("rapid-19", galaxyStore.content)
        val maximum = "a".repeat(ProtocolLimits.AUTOMATIC_CLIPBOARD_BYTES)
        macStore.simulateLocalCopy(AutomaticClipboardKind.Text, maximum)
        assertEquals(maximum, galaxyStore.content)
        macStore.simulateLocalCopy(AutomaticClipboardKind.Text, maximum + "a")
        assertTrue(mac.status is ClipboardAuthorityStatus.Failed)
        assertEquals(maximum, galaxyStore.content)

        mac.stop()
        galaxy.stop()
        macStore.simulateLocalCopy(AutomaticClipboardKind.Text, "after stop")
        assertEquals(maximum, galaxyStore.content)
        val blocked = AutomaticClipboardCoordinator(
            InMemoryClipboardStore(),
            InMemoryClipboardTransport(ClipboardAuthorityStatus.Blocked("no authority")),
            "mac",
            "session-1"
        )
        assertEquals(ClipboardAuthorityStatus.Blocked("no authority"), blocked.start("session-1"))
    }

    @Test
    fun fakeBidirectionalTextAndUrlSync() {
        val mac = ClipboardSyncEngine("mac", "session-1")
        val galaxy = ClipboardSyncEngine("galaxy", "session-1")
        val korean = mac.makeLocalEvent(AutomaticClipboardKind.Text, "한글과 emoji 😀")
        assertEquals(ClipboardReceiveResult.Accepted("한글과 emoji 😀"), galaxy.receive(korean))
        val url = galaxy.makeLocalEvent(AutomaticClipboardKind.Url, "https://example.test/path")
        assertEquals(ClipboardReceiveResult.Accepted("https://example.test/path"), mac.receive(url))
        assertTrue((0 until 20).all {
            galaxy.receive(mac.makeLocalEvent(AutomaticClipboardKind.Text, "item-$it")) is ClipboardReceiveResult.Accepted
        })
    }

    @Test
    fun rejectsLoopReplayBadHashOldSessionAndOversize() {
        val mac = ClipboardSyncEngine("mac", "session-1")
        val galaxy = ClipboardSyncEngine("galaxy", "session-1")
        val local = mac.makeLocalEvent(AutomaticClipboardKind.Text, "same")
        assertEquals(ClipboardReceiveResult.LocalSource, mac.receive(local))
        assertEquals(ClipboardReceiveResult.Accepted("same"), galaxy.receive(local))
        assertEquals(ClipboardReceiveResult.Replayed, galaxy.receive(local))
        assertEquals(
            ClipboardReceiveResult.InvalidHash,
            galaxy.receive(local.copy(sequence = 2, content = "tampered", contentHash = "0".repeat(64)))
        )
        assertEquals(
            ClipboardReceiveResult.InvalidEvent,
            galaxy.receive(local.copy(sourceID = "", sequence = 0, content = "", contentHash = ClipboardEvent.hash("")))
        )
        galaxy.begin("session-2")
        assertEquals(ClipboardReceiveResult.StaleSession, galaxy.receive(local))
        val duplicate = ClipboardEvent.make("mac", "session-2", 1, AutomaticClipboardKind.Text, "same")
        assertEquals(ClipboardReceiveResult.Loop, galaxy.receive(duplicate))
        val maximum = "a".repeat(ProtocolLimits.AUTOMATIC_CLIPBOARD_BYTES)
        assertEquals(maximum, ClipboardEvent.make("mac", "session-2", 2, AutomaticClipboardKind.Text, maximum).content)
        assertFailsWith<ClipboardEventException.ContentTooLarge> {
            ClipboardEvent.make("mac", "session-2", 3, AutomaticClipboardKind.Text, maximum + "a")
        }
    }
}
