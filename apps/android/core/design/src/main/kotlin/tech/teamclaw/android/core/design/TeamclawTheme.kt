package tech.teamclaw.android.core.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Inverse-Hai dark palette. iOS ships light-only; this is an Android
 * extra to match the platform's system-dark convention. Same warm
 * wabi-sabi feel — paper goes from ivory to charcoal, ink stays warm.
 */
internal object HaiDark {
    val Mist          = Color(0xFF1A1916)
    val Paper         = Color(0xFF23211D)
    val Pebble        = Color(0xFF363330)
    val Slate         = Color(0xFF767270)
    val Basalt        = Color(0xFFB3AFA9)
    val Onyx          = Color(0xFFF0EDE8)
    val Cinnabar      = Color(0xFFC95A45)
    val CinnabarDeep  = Color(0xFFA64535)
    val Sage          = Color(0xFF7BA468)
    val Hairline      = Color(0xFFF0EDE8).copy(alpha = 0.10f)
}

private val HaiLightColorScheme = lightColorScheme(
    primary = Hai.Cinnabar,
    onPrimary = Color.White,
    primaryContainer = Hai.Cinnabar.copy(alpha = 0.10f),
    onPrimaryContainer = Hai.Onyx,
    secondary = Hai.Basalt,
    onSecondary = Color.White,
    background = Hai.Mist,
    onBackground = Hai.Onyx,
    surface = Hai.Paper,
    onSurface = Hai.Onyx,
    surfaceVariant = Hai.Pebble,
    onSurfaceVariant = Hai.Basalt,
    outline = Hai.Hairline,
    outlineVariant = Hai.Pebble,
    error = Hai.CinnabarDeep,
    onError = Color.White,
)

private val HaiDarkColorScheme = darkColorScheme(
    primary = HaiDark.Cinnabar,
    onPrimary = Color.White,
    primaryContainer = HaiDark.Cinnabar.copy(alpha = 0.20f),
    onPrimaryContainer = HaiDark.Onyx,
    secondary = HaiDark.Basalt,
    onSecondary = HaiDark.Onyx,
    background = HaiDark.Mist,
    onBackground = HaiDark.Onyx,
    surface = HaiDark.Paper,
    onSurface = HaiDark.Onyx,
    surfaceVariant = HaiDark.Pebble,
    onSurfaceVariant = HaiDark.Basalt,
    outline = HaiDark.Hairline,
    outlineVariant = HaiDark.Pebble,
    error = HaiDark.CinnabarDeep,
    onError = Color.White,
)

/**
 * App-wide theme wrapper. Auto-follows the system dark setting; callers
 * can override by passing [darkTheme] explicitly. Screens that hard-code
 * Hai.* tokens (most of them) stay light-mode visually until they're
 * migrated to MaterialTheme.colorScheme reads — that migration is a
 * follow-up commit; this commit just makes the Material3 components
 * themselves respect dark mode.
 */
@Composable
fun TeamclawTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) HaiDarkColorScheme else HaiLightColorScheme,
        typography = TeamclawTypography,
        content = content,
    )
}
