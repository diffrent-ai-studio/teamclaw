package tech.teamclaw.android.core.auth

import android.net.Uri
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Apple
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import tech.teamclaw.android.core.model.AppBootstrap
import tech.teamclaw.android.core.model.AuthRequired
import tech.teamclaw.android.core.model.ClaimResult
import tech.teamclaw.android.core.model.CreatedTeam
import tech.teamclaw.android.core.model.TeamSummary

/**
 * Kotlin port of iOS SupabaseAppOnboardingStore. Uses supabase-kt 3.x for
 * auth and PostgREST for queries + RPCs.
 *
 * RPCs / tables (must match services/supabase migrations):
 * - actors (member-actor rows per user-team)
 * - team_members (user→team membership with role)
 * - create_team(p_name) RPC → CreatedTeamRow
 * - claim_team_invite(p_token) RPC → ClaimRow
 *
 * NOTE: handleAuthCallback takes a Uri and converts; the real Supabase
 * deeplink handler wants an Android Intent — wire that from the Activity.
 */
class SupabaseOnboardingStore(
    private val client: SupabaseClient,
) : OnboardingStore {

    override suspend fun ensureSession() {
        client.auth.currentSessionOrNull() ?: throw AuthRequired()
    }

    override suspend fun isAnonymous(): Boolean {
        val token = client.auth.currentAccessTokenOrNull() ?: return false
        return decodeJwtIsAnonymous(token)
    }

    override suspend fun loadBootstrap(): AppBootstrap {
        val user = client.auth.currentUserOrNull() ?: throw AuthRequired()
        val userId = user.id.lowercase()

        val actors: List<MemberRow> = client.postgrest.from("actors")
            .select(columns = Columns.list("id")) {
                filter {
                    eq("user_id", userId)
                    eq("actor_type", "member")
                }
            }
            .decodeList()

        if (actors.isEmpty()) {
            return AppBootstrap(memberActorId = null, teams = emptyList())
        }

        val actorIds = actors.map { it.id }
        val memberships: List<MembershipRow> = client.postgrest.from("team_members")
            .select(
                columns = Columns.raw(
                    """
                    role,
                    member_id,
                    teams!inner ( id, name, slug )
                    """.trimIndent()
                )
            ) {
                filter { isIn("member_id", actorIds) }
            }
            .decodeList()

        val teamById = linkedMapOf<String, TeamSummary>()
        val memberByTeam = mutableMapOf<String, String>()
        for (m in memberships) {
            if (m.teams.id !in teamById) {
                teamById[m.teams.id] = TeamSummary(
                    id = m.teams.id, name = m.teams.name, slug = m.teams.slug, role = m.role,
                )
            }
            memberByTeam[m.teams.id] = m.memberId
        }
        val ordered = teamById.values.toList()
        val primary = ordered.firstOrNull()?.let { memberByTeam[it.id] }
        return AppBootstrap(
            memberActorId = primary,
            teams = ordered,
            memberActorIdByTeam = memberByTeam,
        )
    }

    override suspend fun createTeam(name: String): CreatedTeam {
        val rows: List<CreatedTeamRow> = client.postgrest
            .rpc("create_team", buildJsonObject { put("p_name", name) })
            .decodeList()
        val row = rows.firstOrNull()
            ?: throw IllegalStateException("create_team returned no rows")
        return CreatedTeam(
            team = TeamSummary(row.teamId, row.teamName, row.teamSlug, row.role),
            memberActorId = row.memberId,
            workspaceId = row.workspaceId,
            workspaceName = row.workspaceName,
        )
    }

    override suspend fun claimInvite(token: String): ClaimResult {
        val rows: List<ClaimRow> = client.postgrest
            .rpc("claim_team_invite", buildJsonObject { put("p_token", token) })
            .decodeList()
        val row = rows.firstOrNull()
            ?: throw IllegalStateException("claim_team_invite returned no rows")
        return ClaimResult(
            actorId = row.actorId,
            teamId = row.teamId,
            actorType = row.actorType,
            displayName = row.displayName,
            refreshToken = row.refreshToken,
        )
    }

    override suspend fun signIn(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    override suspend fun signUp(email: String, password: String) {
        val result = client.auth.signUpWith(Email) {
            this.email = email
            this.password = password
        }
        if (result == null) {
            throw RuntimeException("Check your inbox — we sent you a confirmation link.")
        }
    }

    override suspend fun sendEmailOtp(email: String) {
        client.auth.signInWith(OTP) {
            this.email = email
            createUser = true
        }
    }

    override suspend fun verifyOtp(email: String, token: String) {
        try {
            client.auth.verifyEmailOtp(type = OtpType.Email.EMAIL, email = email, token = token)
        } catch (_: Throwable) {
            client.auth.verifyEmailOtp(type = OtpType.Email.SIGNUP, email = email, token = token)
        }
    }

    override suspend fun signInWithAppleCredential(idToken: String, nonce: String) {
        client.auth.signInWith(IDToken) {
            this.idToken = idToken
            this.provider = Apple
            this.nonce = nonce
        }
    }

    override suspend fun signInWithGoogle() {
        throw UnsupportedOperationException(
            "Drive Google sign-in via GoogleSignInHandler then call signInWithAppleCredential (IDToken provider Google)"
        )
    }

    override suspend fun signInAnonymously() {
        client.auth.signInAnonymously()
    }

    override suspend fun setSession(refreshToken: String) {
        client.auth.importAuthToken(
            accessToken = "",
            refreshToken = refreshToken,
            retrieveUser = true,
        )
    }

    override suspend fun upgradeWithPassword(email: String, password: String) {
        client.auth.updateUser {
            this.email = email
            this.password = password
        }
    }

    override suspend fun upgradeWithAppleCredential(idToken: String, nonce: String) {
        client.auth.signInWith(IDToken) {
            this.idToken = idToken
            this.provider = Apple
            this.nonce = nonce
        }
    }

    /**
     * Process an auth-callback deep link. supabase-kt's [SupabaseClient.handleDeeplinks]
     * normally takes an Android Intent. We accept a Uri here for store-API uniformity;
     * the caller can pass any Uri (e.g., from Intent.data) and we'll let the auth
     * plugin parse it via its known scheme/host. If the URI is not recognized,
     * this becomes a no-op.
     */
    override suspend fun handleAuthCallback(uri: Uri) {
        // The auth plugin auto-handles deeplinks that match the configured scheme/host
        // when given an Intent. For a bare Uri, we extract the access_token + refresh_token
        // fragment params and import them directly.
        val fragment = uri.fragment ?: uri.query ?: return
        val params = fragment.split("&").mapNotNull { kv ->
            val eq = kv.indexOf('=')
            if (eq < 0) null else kv.substring(0, eq) to kv.substring(eq + 1)
        }.toMap()
        val access = params["access_token"]
        val refresh = params["refresh_token"]
        if (!access.isNullOrEmpty() && !refresh.isNullOrEmpty()) {
            client.auth.importAuthToken(
                accessToken = access,
                refreshToken = refresh,
                retrieveUser = true,
            )
        }
    }

    override suspend fun accessToken(): String =
        client.auth.currentAccessTokenOrNull() ?: throw AuthRequired()

    override suspend fun signOut() {
        client.auth.signOut()
    }

    override fun tokenRefreshes(): Flow<Unit> =
        client.auth.sessionStatus
            .filter { it is SessionStatus.Authenticated }
            .map { }

    /**
     * Decode the middle JWT segment (Base64URL) and look up `is_anonymous`.
     * No signature verification — purely for client-side UI affordances.
     */
    private fun decodeJwtIsAnonymous(jwt: String): Boolean {
        val parts = jwt.split(".")
        if (parts.size < 2) return false
        val payload = parts[1]
        val padded = payload + "=".repeat((4 - payload.length % 4) % 4)
        val decoded = try {
            android.util.Base64.decode(padded, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
        } catch (_: Throwable) {
            return false
        }
        val json = runCatching { Json.parseToJsonElement(decoded.toString(Charsets.UTF_8)) as? JsonObject }
            .getOrNull() ?: return false
        return json["is_anonymous"]?.jsonPrimitive?.content?.toBooleanStrictOrNull() ?: false
    }

    // ---- RPC params & response shapes ----

    @Serializable
    private data class MemberRow(val id: String)

    @Serializable
    private data class MembershipRow(
        val role: String,
        @SerialName("member_id") val memberId: String,
        val teams: TeamRow,
    )

    @Serializable
    private data class TeamRow(val id: String, val name: String, val slug: String)

    @Serializable
    private data class CreatedTeamRow(
        @SerialName("team_id") val teamId: String,
        @SerialName("team_name") val teamName: String,
        @SerialName("team_slug") val teamSlug: String,
        @SerialName("member_id") val memberId: String,
        val role: String,
        @SerialName("workspace_id") val workspaceId: String,
        @SerialName("workspace_name") val workspaceName: String,
    )

    @Serializable
    private data class ClaimRow(
        @SerialName("actor_id") val actorId: String,
        @SerialName("team_id") val teamId: String,
        @SerialName("actor_type") val actorType: String,
        @SerialName("display_name") val displayName: String,
        @SerialName("refresh_token") val refreshToken: String?,
    )
}
