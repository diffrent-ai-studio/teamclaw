package tech.teamclaw.android.core.model

data class AppBootstrap(
    val memberActorId: String?,
    val teams: List<TeamSummary>,
    val memberActorIdByTeam: Map<String, String> = emptyMap(),
)
