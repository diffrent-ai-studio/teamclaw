package tech.teamclaw.android.core.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest

object SupabaseClientFactory {
    fun create(config: SupabaseConfig): SupabaseClient = createSupabaseClient(
        supabaseUrl = config.url,
        supabaseKey = config.publishableKey,
    ) {
        install(Auth) {
            scheme = "teamclaw"
            host = "auth-callback"
        }
        install(Postgrest)
    }
}
