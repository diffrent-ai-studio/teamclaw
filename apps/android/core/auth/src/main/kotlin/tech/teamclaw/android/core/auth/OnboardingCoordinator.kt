package tech.teamclaw.android.core.auth

import android.net.Uri
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import tech.teamclaw.android.core.model.AppContext
import tech.teamclaw.android.core.model.AuthRequired
import tech.teamclaw.android.core.model.TeamSummary

/**
 * Kotlin port of iOS AppOnboardingCoordinator. State machine:
 * Loading → (NeedsAuth | Ready | CreateTeam | Failed).
 */
class OnboardingCoordinator(
    val store: OnboardingStore,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + dispatcher),
) {
    private val _state = MutableStateFlow(OnboardingState())
    val state: StateFlow<OnboardingState> = _state.asStateFlow()

    fun launch(block: suspend () -> Unit) {
        scope.launch(dispatcher) { block() }
    }

    // ---- Bootstrap ----

    suspend fun bootstrap(preferringTeamId: String? = null) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, route = OnboardingRoute.Loading, errorMessage = null) }

        try {
            try {
                store.ensureSession()
            } catch (_: AuthRequired) {
                _state.update {
                    it.copy(
                        route = OnboardingRoute.NeedsAuth,
                        currentContext = null,
                        isAnonymous = false,
                        isBusy = false,
                    )
                }
                return
            }

            val anon = store.isAnonymous()
            var bootstrap = store.loadBootstrap()
            var preferred = preferringTeamId

            val pendingToken = _state.value.pendingInviteToken
            if (!pendingToken.isNullOrEmpty()) {
                try {
                    val claim = store.claimInvite(pendingToken)
                    _state.update { it.copy(pendingInviteToken = null) }
                    preferred = preferred ?: claim.teamId
                    bootstrap = store.loadBootstrap()
                } catch (t: Throwable) {
                    _state.update { it.copy(pendingInviteToken = null) }
                    runCatching { store.signOut() }
                    _state.update {
                        it.copy(
                            errorMessage = t.message ?: "Failed to redeem invite.",
                            currentContext = null,
                            isAnonymous = false,
                            route = OnboardingRoute.NeedsAuth,
                            isBusy = false,
                        )
                    }
                    return
                }
            }

            val pickedTeam: TeamSummary? = preferred
                ?.let { id -> bootstrap.teams.firstOrNull { it.id == id } }
                ?: bootstrap.teams.firstOrNull()

            val pickedActorId: String? = pickedTeam
                ?.let { bootstrap.memberActorIdByTeam[it.id] ?: bootstrap.memberActorId }

            if (pickedTeam != null && pickedActorId != null) {
                _state.update {
                    it.copy(
                        route = OnboardingRoute.Ready,
                        currentContext = AppContext(pickedTeam, pickedActorId),
                        isAnonymous = anon,
                        isBusy = false,
                    )
                }
                return
            }

            // No team — auto-create.
            val created = store.createTeam(RandomTeamName.generate())
            _state.update {
                it.copy(
                    route = OnboardingRoute.Ready,
                    currentContext = AppContext(created.team, created.memberActorId),
                    pendingCreatedTeam = created,
                    isAnonymous = anon,
                    isBusy = false,
                )
            }
        } catch (t: Throwable) {
            _state.update {
                it.copy(
                    route = OnboardingRoute.Failed,
                    currentContext = null,
                    isAnonymous = false,
                    errorMessage = t.message ?: t::class.simpleName,
                    isBusy = false,
                )
            }
        }
    }

    // ---- Create team (manual) ----

    suspend fun createTeam(rawName: String) {
        val name = rawName.trim()
        if (name.isEmpty()) {
            _state.update { it.copy(route = OnboardingRoute.CreateTeam, errorMessage = "Team name is required.") }
            return
        }
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        try {
            val created = store.createTeam(name)
            _state.update {
                it.copy(
                    pendingCreatedTeam = created,
                    currentContext = AppContext(created.team, created.memberActorId),
                    route = OnboardingRoute.Ready,
                    isBusy = false,
                )
            }
        } catch (t: Throwable) {
            _state.update {
                it.copy(route = OnboardingRoute.CreateTeam, errorMessage = t.message, isBusy = false)
            }
        }
    }

    // ---- Email OTP ----

    suspend fun sendEmailOtp(email: String) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        try {
            store.sendEmailOtp(email)
            _state.update { it.copy(pendingEmailOtpEmail = email, isBusy = false) }
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isBusy = false) }
        }
    }

    suspend fun verifyOtp(email: String, token: String) {
        performAuth { store.verifyOtp(email, token) }
    }

    fun resetPendingEmailOtp() {
        _state.update { it.copy(pendingEmailOtpEmail = null, errorMessage = null) }
    }

    // ---- Other auth methods ----

    suspend fun signIn(email: String, password: String) = performAuth {
        store.signIn(email, password)
    }
    suspend fun signUp(email: String, password: String) = performAuth {
        store.signUp(email, password)
    }
    suspend fun signInAnonymously() = performAuth { store.signInAnonymously() }

    suspend fun signInWithAppleCredential(idToken: String, nonce: String) = performAuth {
        store.signInWithAppleCredential(idToken, nonce)
    }
    suspend fun signInWithGoogle() = performAuth { store.signInWithGoogle() }

    suspend fun signInAnonymouslyAndClaim(token: String) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        try {
            store.signInAnonymously()
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isBusy = false) }
            return
        }
        try {
            val claim = store.claimInvite(token)
            _state.update { it.copy(isBusy = false) }
            bootstrap(preferringTeamId = claim.teamId)
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isBusy = false) }
            runCatching { store.signOut() }
        }
    }

    suspend fun claimInviteSmart(token: String) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }

        runCatching { store.signOut() }

        val claim = try {
            store.claimInvite(token)
        } catch (_: Throwable) {
            _state.update { it.copy(isBusy = false) }
            signInAnonymouslyAndClaim(token)
            return
        }

        val rt = claim.refreshToken
        if (rt != null) {
            try {
                store.setSession(rt)
            } catch (t: Throwable) {
                _state.update {
                    it.copy(
                        errorMessage = "Sign-in failed after redeeming the invite. " +
                            "Ask the team admin for a fresh link. (${t.message})",
                        isBusy = false,
                    )
                }
                return
            }
            _state.update { it.copy(isBusy = false) }
            bootstrap(preferringTeamId = claim.teamId)
            return
        }

        _state.update { it.copy(isBusy = false) }
        bootstrap(preferringTeamId = claim.teamId)
    }

    suspend fun upgradeWithPassword(email: String, password: String) = performAuth {
        store.upgradeWithPassword(email, password)
    }
    suspend fun upgradeWithApple(idToken: String, nonce: String) = performAuth {
        store.upgradeWithAppleCredential(idToken, nonce)
    }

    suspend fun accessToken(): String = store.accessToken()

    suspend fun signOut() {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        runCatching { store.signOut() }.onFailure { t ->
            _state.update { it.copy(errorMessage = t.message) }
        }
        _state.update {
            it.copy(
                currentContext = null,
                pendingCreatedTeam = null,
                pendingEmailOtpEmail = null,
                isAnonymous = false,
                route = OnboardingRoute.NeedsAuth,
                isBusy = false,
            )
        }
    }

    suspend fun handleAuthCallback(uri: Uri) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        try {
            store.handleAuthCallback(uri)
            _state.update { it.copy(pendingEmailOtpEmail = null, isBusy = false) }
            bootstrap()
        } catch (t: Throwable) {
            _state.update { it.copy(isBusy = false, errorMessage = t.message) }
        }
    }

    fun setPendingInviteToken(token: String?) {
        _state.update { it.copy(pendingInviteToken = token) }
    }

    private suspend fun performAuth(action: suspend () -> Unit) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, errorMessage = null) }
        try {
            action()
            _state.update { it.copy(isBusy = false) }
            bootstrap()
        } catch (t: Throwable) {
            _state.update { it.copy(isBusy = false, errorMessage = t.message) }
        }
    }
}
