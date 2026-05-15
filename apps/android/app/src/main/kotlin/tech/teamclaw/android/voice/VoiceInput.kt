package tech.teamclaw.android.voice

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import java.util.Locale

/**
 * Thin wrapper around the platform speech recognizer. The recognizer
 * intent opens the system speech UI; results land in onResult or are
 * silently dropped on cancellation / unsupported devices.
 */
class VoiceInput(activity: ComponentActivity) {

    private var onResult: ((String) -> Unit)? = null

    private val launcher: ActivityResultLauncher<Intent> = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val matches = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val transcript = matches?.firstOrNull()?.takeIf { it.isNotBlank() }
            if (transcript != null) onResult?.invoke(transcript)
        }
        onResult = null
    }

    fun listen(onResult: (String) -> Unit) {
        this.onResult = onResult
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your message")
        }
        runCatching { launcher.launch(intent) }
    }
}
