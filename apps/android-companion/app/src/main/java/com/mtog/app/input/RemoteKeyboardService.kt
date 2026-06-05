package com.mtog.app.input

import android.inputmethodservice.InputMethodService
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout

class RemoteKeyboardService : InputMethodService() {
    override fun onCreate() {
        super.onCreate()
        RemoteKeyboardBridge.attach(this)
    }

    override fun onDestroy() {
        RemoteKeyboardBridge.detach(this)
        RemoteKeyboardRuntime.markServiceDetached(this)
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        return FrameLayout(this).apply {
            alpha = 0f
            isClickable = false
            isFocusable = false
            minimumHeight = 1
        }
    }

    override fun onEvaluateInputViewShown(): Boolean {
        super.onEvaluateInputViewShown()
        return false
    }

    override fun onShowInputRequested(flags: Int, configChange: Boolean): Boolean {
        return false
    }

    override fun onEvaluateFullscreenMode(): Boolean {
        return false
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        RemoteKeyboardRuntime.markServiceAttached(this)
        setCandidatesViewShown(false)
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        RemoteKeyboardRuntime.markServiceAttached(this)
        window?.window?.decorView?.alpha = 0f
        setCandidatesViewShown(false)
    }

    override fun onFinishInput() {
        super.onFinishInput()
        RemoteKeyboardRuntime.markServiceDetached(this)
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        if (finishingInput) {
            RemoteKeyboardRuntime.markServiceDetached(this)
        }
    }

    fun commitRemoteText(text: String): Boolean {
        if (text.isEmpty()) {
            return false
        }

        val inputConnection = currentInputConnection ?: return false
        inputConnection.beginBatchEdit()
        inputConnection.finishComposingText()
        val committed = inputConnection.commitText(text, 1)
        inputConnection.endBatchEdit()
        return committed
    }

    fun deleteRemoteBackward(): Boolean {
        val inputConnection = currentInputConnection ?: return false
        return inputConnection.deleteSurroundingTextInCodePoints(1, 0) ||
            inputConnection.deleteSurroundingText(1, 0)
    }

    fun performRemoteEnter(): Boolean {
        sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
        return true
    }
}
