package tech.teamclaw.android.core.deeplink

import android.net.Uri

class DeepLinkParser {
    /**
     * Map a Uri intent to its semantic DeepLink, or null if not one we own.
     * Mirrors iOS AMUXApp.swift handle(_:) switch on url.host.
     */
    fun parse(uri: Uri): DeepLink? {
        if (uri.scheme !in KNOWN_SCHEMES) return null
        return when (uri.host) {
            "invite" -> uri.getQueryParameter("token")
                ?.takeIf { it.isNotBlank() }
                ?.let { DeepLink.InviteToken(it) }
            "auth-callback" -> DeepLink.AuthCallback(uri)
            else -> null
        }
    }

    /**
     * Accept either a full deeplink URL or a bare token string. Port of
     * iOS InviteJoinSheet.parseToken(_:). Returns null on empty / malformed.
     */
    fun parseToken(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        if ("://" in trimmed) {
            val uri = runCatching { Uri.parse(trimmed) }.getOrNull() ?: return null
            if (uri.scheme !in KNOWN_SCHEMES) return null
            if (uri.host != "invite") return null
            return uri.getQueryParameter("token")?.takeIf { it.isNotBlank() }
        }
        return trimmed
    }

    private companion object {
        val KNOWN_SCHEMES = setOf("teamclaw", "amux")
    }
}
