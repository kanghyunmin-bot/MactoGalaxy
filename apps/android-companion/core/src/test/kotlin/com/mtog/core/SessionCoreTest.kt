package com.mtog.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionCoreTest {
    @Test
    fun replayGuardBindsSessionTokenAndGeneration() {
        val guard = SessionReplayGuard()
        guard.begin("s1", "t1", "c1", "n1", 4)
        assertTrue(guard.accept("s1", "t1", "c1", "n1", 1, 4))
        assertFalse(guard.accept("s1", "t1", "c1", "n1", 1, 4))
        assertFalse(guard.accept("s1", "old", "c1", "n1", 2, 4))
        assertFalse(guard.accept("s1", "t1", "c1", "old", 2, 4))
        guard.begin("s2", "t2", "c2", "n2", 5)
        assertTrue(guard.accept("s2", "t2", "c2", "n2", 1, 5))
        assertFalse(guard.accept("s1", "t1", "c1", "n1", 3, 4))
    }

    @Test
    fun reconnectAndStopRules() {
        val policy = ReconnectPolicy(8, 1, 16)
        assertEquals(listOf(1, 2, 4, 8, 16, 16, 16, 16), (1..8).mapNotNull(policy::delaySeconds))
        assertNull(policy.delaySeconds(9))
        val machine = SessionStateMachine()
        machine.handle(SessionEvent.Start)
        machine.handle(SessionEvent.Connected)
        machine.handle(SessionEvent.UserStopped)
        machine.handle(SessionEvent.TransportFailed)
        assertEquals(SessionState.StoppedByUser, machine.state)
    }

    @Test
    fun negotiationGeometryAndQueue() {
        val result = CodecNegotiator.negotiate(
            CodecCapabilities(listOf(VideoCodec.Hevc, VideoCodec.H264), 2560, 1600, 60),
            CodecCapabilities(listOf(VideoCodec.H264), 1920, 1080, 30)
        )
        assertEquals(VideoCodec.H264, result.codec)
        assertEquals(1920, result.width)
        assertEquals(1080, result.height)
        assertEquals(30, result.framesPerSecond)
        assertFailsWith<IllegalArgumentException> {
            CodecNegotiator.negotiate(
                CodecCapabilities(listOf(VideoCodec.H264), 1, 1, 1),
                CodecCapabilities(emptyList(), 1, 1, 1)
            )
        }
        assertEquals(DisplayPoint(50, 75), DisplayGeometry.mapNormalized(0.25, 0.75, 200, 100))
        assertEquals(DisplayPoint(4, 4), DisplayGeometry.mapNormalized(0.36, 0.36, 10, 10))
        assertFailsWith<IllegalArgumentException> {
            DisplayGeometry.mapNormalized(-0.1, 0.5, 200, 100)
        }
        val queue = LatestValueQueue<Int>(2)
        assertNull(queue.append(1))
        assertNull(queue.append(2))
        assertEquals(1, queue.append(3))
        assertEquals(listOf(2, 3), queue.values)
    }
}
