package com.mtog.app.externaldisplay

import android.content.Intent
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mtog.app.ExternalDisplayActivity
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SurfaceSessionInstrumentationTest {
    private fun surface(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            surface(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    @Test fun replacementSessionRecreatesSurfaceAndRecreationSurvives() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun intent() = Intent(context, ExternalDisplayActivity::class.java)
            .putExtra("sessionId", UUID.randomUUID().toString())
            .putExtra("port", 46192).putExtra("inputPort", 46193)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        ActivityScenario.launch<ExternalDisplayActivity>(intent()).use { scenario ->
            fun awaitSurface(previous: SurfaceView? = null): SurfaceView? {
                var found: SurfaceView? = null
                repeat(80) {
                    scenario.onActivity { found = surface(it.window.decorView) }
                    if (found != null && found !== previous && found!!.holder.surface.isValid) return found
                    Thread.sleep(50)
                }
                return found
            }
            val first = awaitSurface()
            assertNotNull(first)
            context.startActivity(intent())
            val replacement = awaitSurface(first)
            assertNotNull(replacement)
            assertNotSame(first, replacement)
            scenario.recreate()
            assertNotSame(replacement, awaitSurface(replacement))
        }
    }
}
