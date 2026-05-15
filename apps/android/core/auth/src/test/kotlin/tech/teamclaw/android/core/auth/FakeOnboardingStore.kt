package tech.teamclaw.android.core.auth

import android.net.Uri
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import tech.teamclaw.android.core.model.AppBootstrap
import tech.teamclaw.android.core.model.AuthRequired
import tech.teamclaw.android.core.model.ClaimResult
import tech.teamclaw.android.core.model.CreatedTeam
import tech.teamclaw.android.core.model.TeamSummary

/**
 * In-memory test double. Records every call; returns pre-canned values or
 * pre-canned errors. Mirrors iOS FailingOnboardingStore pattern.
 */
class FakeOnboardingStore : OnboardingStore {

    data class Call(val name: String, val args: Map<String, Any?> = emptyMap())

    val calls = mutableListOf<Call>()
    private val refreshFlow = MutableSharedFlow<Unit>(extraBufferCapacity = 8)

    var sessionExists: Boolean = false
    var isAnonymousValue: Boolean = false
    var bootstrapResult: AppBootstrap = AppBootstrap(memberActorId = null, teams = emptyList())
    var createTeamResult: CreatedTeam = sampleCreatedTeam("Auto Team")
    var claimResult: ClaimResult? = null
    var claimError: Throwable? = null
    var signInError: Throwable? = null
    var sendOtpError: Throwable? = null
    var verifyOtpError: Throwable? = null
    var anonymousError: Throwable? = null
    var bootstrapError: Throwable? = null

    override suspend fun ensureSession() {
        calls += Call("ensureSession")
        if (!sessionExists) throw AuthRequired()
    }

    override suspend fun loadBootstrap(): AppBootstrap {
        calls += Call("loadBootstrap")
        bootstrapError?.let { throw it }
        return bootstrapResult
    }

    override suspend fun createTeam(name: String): CreatedTeam {
        calls += Call("createTeam", mapOf("name" to name))
        return createTeamResult
    }

    override suspend fun claimInvite(token: String): ClaimResult {
        calls += Call("claimInvite", mapOf("token" to token))
        claimError?.let { throw it }
        return claimResult ?: error("claimResult not set")
    }

    override suspend fun signIn(email: String, password: String) {
        calls += Call("signIn", mapOf("email" to email))
        signInError?.let { throw it }
        sessionExists = true
    }

    override suspend fun signUp(email: String, password: String) {
        calls += Call("signUp", mapOf("email" to email))
        signInError?.let { throw it }
        sessionExists = true
    }

    override suspend fun sendEmailOtp(email: String) {
        calls += Call("sendEmailOtp", mapOf("email" to email))
        sendOtpError?.let { throw it }
    }

    override suspend fun verifyOtp(email: String, token: String) {
        calls += Call("verifyOtp", mapOf("email" to email, "token" to token))
        verifyOtpError?.let { throw it }
        sessionExists = true
    }

    override suspend fun signInWithAppleCredential(idToken: String, nonce: String) {
        calls += Call("signInWithAppleCredential")
        sessionExists = true
    }

    override suspend fun signInWithGoogle() {
        calls += Call("signInWithGoogle")
        sessionExists = true
    }

    override suspend fun signInAnonymously() {
        calls += Call("signInAnonymously")
        anonymousError?.let { throw it }
        sessionExists = true
        isAnonymousValue = true
    }

    override suspend fun handleAuthCallback(uri: Uri) {
        calls += Call("handleAuthCallback")
        sessionExists = true
    }

    override suspend fun accessToken(): String {
        calls += Call("accessToken")
        return "fake-access-token"
    }

    override suspend fun signOut() {
        calls += Call("signOut")
        sessionExists = false
        isAnonymousValue = false
    }

    override suspend fun setSession(refreshToken: String) {
        calls += Call("setSession", mapOf("refreshToken" to refreshToken))
        sessionExists = true
    }

    override suspend fun isAnonymous(): Boolean {
        calls += Call("isAnonymous")
        return isAnonymousValue
    }

    override suspend fun upgradeWithPassword(email: String, password: String) {
        calls += Call("upgradeWithPassword", mapOf("email" to email))
    }

    override suspend fun upgradeWithAppleCredential(idToken: String, nonce: String) {
        calls += Call("upgradeWithAppleCredential")
    }

    override fun tokenRefreshes(): Flow<Unit> = refreshFlow

    suspend fun emitTokenRefresh() = refreshFlow.emit(Unit)

    fun callNames(): List<String> = calls.map { it.name }

    companion object {
        fun sampleTeam(
            id: String = "team-1",
            name: String = "Sample Team",
            slug: String = "sample-team",
            role: String = "owner",
        ) = TeamSummary(id, name, slug, role)

        fun sampleCreatedTeam(name: String = "Sample") = CreatedTeam(
            team = sampleTeam(name = name),
            memberActorId = "actor-1",
            workspaceId = "ws-1",
            workspaceName = "$name Workspace",
        )
    }
}
