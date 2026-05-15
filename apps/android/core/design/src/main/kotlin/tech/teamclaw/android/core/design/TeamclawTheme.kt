package tech.teamclaw.android.core.design

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

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

/**
 * Single app-wide theme wrapper. Dark mode falls back to the same light
 * scheme for P1 — iOS ships light-only too.
 */
@Composable
fun TeamclawTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = HaiLightColorScheme,
        typography = TeamclawTypography,
        content = content,
    )
}
