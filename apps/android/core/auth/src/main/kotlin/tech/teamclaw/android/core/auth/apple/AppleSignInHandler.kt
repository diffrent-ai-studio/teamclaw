package tech.teamclaw.android.core.auth.apple

import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.suspendCancellableCoroutine
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import java.security.SecureRandom
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Apple Sign-In via AppAuth-Android (OIDC). Returns (idToken, nonce) which
 * the OnboardingStore feeds to Supabase signInWithIdToken.
 *
 * Requires APPLE_SERVICE_ID configured (Apple Service ID with the app's
 * redirect URI registered). Throws AppleSignInUnconfiguredException when blank.
 */
class AppleSignInHandler(
    private val serviceId: String,
    private val redirectUri: String = "teamclaw://auth-callback",
) {
    class AppleSignInUnconfiguredException :
        RuntimeException("APPLE_SERVICE_ID is not configured. Apple sign-in disabled.")

    data class Credential(val idToken: String, val nonce: String)

    suspend fun request(activity: ComponentActivity): Credential {
        if (serviceId.isBlank()) throw AppleSignInUnconfiguredException()
        val nonce = generateNonce()
        val config = AuthorizationServiceConfiguration(
            android.net.Uri.parse("https://appleid.apple.com/auth/authorize"),
            android.net.Uri.parse("https://appleid.apple.com/auth/token"),
        )
        val request = AuthorizationRequest.Builder(
            config,
            serviceId,
            ResponseTypeValues.CODE,
            android.net.Uri.parse(redirectUri),
        )
            .setScope("name email")
            .setNonce(nonce)
            .build()
        return performAuth(activity, request, nonce)
    }

    private suspend fun performAuth(
        activity: ComponentActivity,
        request: AuthorizationRequest,
        nonce: String,
    ): Credential = suspendCancellableCoroutine { cont ->
        val service = AuthorizationService(activity)
        val launcher = activity.activityResultRegistry.register(
            "apple-signin-${System.nanoTime()}",
            ActivityResultContracts.StartActivityForResult(),
        ) { result ->
            val data = result.data
            if (data == null) {
                cont.resumeWithException(RuntimeException("Apple sign-in cancelled"))
                return@register
            }
            val resp = AuthorizationResponse.fromIntent(data)
            val err = AuthorizationException.fromIntent(data)
            if (err != null || resp == null) {
                cont.resumeWithException(err ?: RuntimeException("Apple sign-in failed"))
                return@register
            }
            service.performTokenRequest(resp.createTokenExchangeRequest()) { tokenResp, tokenErr ->
                if (tokenErr != null || tokenResp?.idToken == null) {
                    cont.resumeWithException(tokenErr ?: RuntimeException("Missing id_token"))
                } else {
                    cont.resume(Credential(tokenResp.idToken!!, nonce))
                }
            }
        }
        val intent: Intent = service.getAuthorizationRequestIntent(request)
        launcher.launch(intent)
        cont.invokeOnCancellation { service.dispose() }
    }

    private fun generateNonce(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
