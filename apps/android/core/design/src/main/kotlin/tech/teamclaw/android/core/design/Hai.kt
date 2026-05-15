package tech.teamclaw.android.core.design

import androidx.compose.ui.graphics.Color

/**
 * Hai 灰 wabi-sabi palette — port of iOS AMUXTheme.swift.
 * Six paper/ink neutrals + restrained vermillion accent. "Spare the
 * vermillion" — Cinnabar only on active CTAs, unread dots, permission
 * markers. Everywhere else: Mist / Pebble / Slate / Basalt / Onyx.
 */
object Hai {
    val Mist          = Color(0xFFF2F0EC)
    val Paper         = Color(0xFFF8F6F1)
    val Pebble        = Color(0xFFE2DFD9)
    val Slate         = Color(0xFFA6A39C)
    val Basalt        = Color(0xFF5E5B55)
    val Onyx          = Color(0xFF22201D)
    val Cinnabar      = Color(0xFFB84B36)
    val CinnabarDeep  = Color(0xFF8E3A2C)
    val Sage          = Color(0xFF6B8E5A)
    val Hairline      = Color(0xFF22201D).copy(alpha = 0.10f)
}
