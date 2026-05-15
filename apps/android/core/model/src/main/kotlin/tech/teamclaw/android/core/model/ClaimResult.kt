package tech.teamclaw.android.core.model

data class ClaimResult(
    val actorId: String,
    val teamId: String,
    val actorType: String,
    val displayName: String,
    /** Non-null only for agent / member-reinvite claims. */
    val refreshToken: String?,
)
