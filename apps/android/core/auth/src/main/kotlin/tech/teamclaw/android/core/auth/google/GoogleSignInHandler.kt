package tech.teamclaw.android.core.auth.google

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/**
 * Google Sign-In via AndroidX Credential Manager + googleid provider.
 * Returns the Google ID token; Supabase signInWithIdToken accepts Google
 * credentials without a nonce.
 */
class GoogleSignInHandler(
    private val clientId: String,
) {
    class GoogleSignInUnconfiguredException :
        RuntimeException("GOOGLE_OAUTH_CLIENT_ID is not configured. Google sign-in disabled.")

    data class Credential(val idToken: String)

    suspend fun request(context: Context): Credential {
        if (clientId.isBlank()) throw GoogleSignInUnconfiguredException()
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(clientId)
            .setFilterByAuthorizedAccounts(false)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val result = CredentialManager.create(context).getCredential(context, request)
        val gid = GoogleIdTokenCredential.createFrom(result.credential.data)
        return Credential(gid.idToken)
    }
}
