package tech.teamclaw.android.core.deeplink

import android.net.Uri

sealed interface DeepLink {
    data class InviteToken(val token: String) : DeepLink
    data class AuthCallback(val uri: Uri) : DeepLink
}
