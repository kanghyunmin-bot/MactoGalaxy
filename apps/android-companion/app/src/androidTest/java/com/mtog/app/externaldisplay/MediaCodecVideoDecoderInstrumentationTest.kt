package com.mtog.app.externaldisplay

import android.media.MediaCodec
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mtog.core.VideoCodec
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaCodecVideoDecoderInstrumentationTest {
    @Test
    fun advertisedDecodersCanBeCreated() {
        val capabilities = CodecCapabilityReader.read()
        assertTrue(capabilities.codecs.isNotEmpty())
        capabilities.codecs.forEach { codec ->
            val mime = if (codec == VideoCodec.H264) "video/avc" else "video/hevc"
            MediaCodec.createDecoderByType(mime).release()
        }
    }
}
