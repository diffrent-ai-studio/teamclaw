package tech.teamclaw.android.core.auth

import android.net.Uri
import kotlinx.coroutines.flow.Flow
import tech.teamclaw.android.core.model.AppBootstrap
import tech.teamclaw.android.core.model.ClaimResult
import tech.teamclaw.android.core.model.CreatedTeam

interface OnboardingStore {
    suspend fun ensureSession()
    suspend fun loadBootstrap(): AppBootstrap
    suspend fun createTeam(name: String): CreatedTeam
    suspend fun claimInvite(token: String): ClaimResult

    suspend fun signIn(email: String, password: String)
    suspend fun signUp(email: String, password: String)
    suspend fun sendEmailOtp(email: String)
    suspend fun verifyOtp(email: String, token: String)
    suspend fun signInWithAppleCredential(idToken: String, nonce: String)
    suspend fun signInWithGoogle()
    suspend fun signInAnonymously()
    suspend fun handleAuthCallback(uri: Uri)
    suspend fun accessToken(): String
    suspend fun signOut()
    suspend fun setSession(refreshToken: String)

    suspend fun isAnonymous(): Boolean
    suspend fun upgradeWithPassword(email: String, password: String)
    suspend fun upgradeWithAppleCredential(idToken: String, nonce: String)

    fun tokenRefreshes(): Flow<Unit>
}
