package tech.teamclaw.android.core.model

import kotlinx.serialization.Serializable

@Serializable
data class TeamSummary(
    val id: String,
    val name: String,
    val slug: String,
    val role: String,
)
