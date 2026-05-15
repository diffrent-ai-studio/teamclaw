package tech.teamclaw.android.core.auth

object RandomTeamName {
    private val adjectives = listOf(
        "Quiet", "Curious", "Bold", "Steady", "Bright", "Gentle",
        "Sharp", "Calm", "Eager", "Patient", "Brave", "Witty",
    )
    private val nouns = listOf(
        "River", "Meadow", "Harbor", "Lantern", "Cinder", "Cobble",
        "Atlas", "Cipher", "Compass", "Echo", "Forge", "Garden",
    )

    fun generate(): String {
        val adj = adjectives.random()
        val noun = nouns.random()
        return "$adj $noun"
    }
}
