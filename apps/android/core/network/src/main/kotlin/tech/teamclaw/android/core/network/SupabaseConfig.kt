package tech.teamclaw.android.core.network

data class SupabaseConfig(
    val url: String,
    val publishableKey: String,
) {
    init {
        require(url.isNotBlank()) { "SUPABASE_URL missing" }
        require(publishableKey.isNotBlank()) { "SUPABASE_PUBLISHABLE_KEY missing" }
    }
}
