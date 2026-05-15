package tech.teamclaw.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import tech.teamclaw.android.core.deeplink.DeepLink
import tech.teamclaw.android.core.design.TeamclawTheme
import tech.teamclaw.android.nav.TeamclawNavHost
import tech.teamclaw.android.voice.VoiceInput

class MainActivity : ComponentActivity() {

    private val app get() = application as TeamclawApplication
    private lateinit var voiceInput: VoiceInput

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        voiceInput = VoiceInput(this)
        intent?.let { handleIntent(it) }
        setContent {
            TeamclawTheme {
                TeamclawNavHost(
                    coordinator = app.coordinator,
                    appleHandler = app.appleHandler,
                    googleHandler = app.googleHandler,
                    sessionListStoreFactory = app.sessionListStoreFactory,
                    sessionDetailStoreFactory = app.sessionDetailStoreFactory,
                    actorStoreFactory = app.actorStoreFactory,
                    versionName = BuildConfig.VERSION_NAME,
                    versionCode = BuildConfig.VERSION_CODE,
                    onStartVoiceInput = voiceInput::listen,
                    onSessionReady = { actorId ->
                        runCatching {
                            val token = app.coordinator.accessToken()
                            app.mqttService.connect(actorId, token)
                        }
                    },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val data = intent.data ?: return
        val deepLink = app.deepLinkParser.parse(data) ?: return
        lifecycleScope.launch {
            when (deepLink) {
                is DeepLink.InviteToken -> app.coordinator.setPendingInviteToken(deepLink.token)
                is DeepLink.AuthCallback -> app.coordinator.handleAuthCallback(data)
            }
        }
    }
}
