package tech.teamclaw.android.core.model

data class CreatedTeam(
    val team: TeamSummary,
    val memberActorId: String,
    val workspaceId: String,
    val workspaceName: String,
)
