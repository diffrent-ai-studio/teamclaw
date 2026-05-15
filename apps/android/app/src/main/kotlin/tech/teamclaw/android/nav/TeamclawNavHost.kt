package tech.teamclaw.android.nav

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import tech.teamclaw.android.core.auth.OnboardingCoordinator
import tech.teamclaw.android.core.auth.OnboardingRoute
import tech.teamclaw.android.core.auth.SessionDetailStore
import tech.teamclaw.android.core.auth.SessionListStore
import tech.teamclaw.android.core.auth.apple.AppleSignInHandler
import tech.teamclaw.android.core.auth.google.GoogleSignInHandler
import tech.teamclaw.android.core.model.SessionRecord
import tech.teamclaw.android.feature.onboarding.ChooseAuthScreen
import tech.teamclaw.android.feature.onboarding.CreateTeamScreen
import tech.teamclaw.android.feature.onboarding.InviteJoinSheet
import tech.teamclaw.android.feature.onboarding.LobsterSplashScreen
import tech.teamclaw.android.feature.onboarding.LoginScreen
import tech.teamclaw.android.feature.onboarding.OnboardingErrorScreen
import tech.teamclaw.android.feature.onboarding.SessionDetailScreen
import tech.teamclaw.android.feature.onboarding.SessionListScreen
import tech.teamclaw.android.feature.onboarding.WelcomeScreen

@Composable
fun TeamclawNavHost(
    coordinator: OnboardingCoordinator,
    appleHandler: AppleSignInHandler,
    googleHandler: GoogleSignInHandler,
    sessionListStoreFactory: (teamId: String) -> SessionListStore,
    sessionDetailStoreFactory: (teamId: String, sessionId: String, currentActorId: String) -> SessionDetailStore,
) {
    val state by coordinator.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current as ComponentActivity

    LaunchedEffect(Unit) { coordinator.bootstrap() }

    when (state.route) {
        OnboardingRoute.Loading -> LobsterSplashScreen()
        OnboardingRoute.Failed -> OnboardingErrorScreen(
            message = state.errorMessage ?: "Unknown setup error.",
            onRetry = { coordinator.launch { coordinator.bootstrap() } },
        )
        OnboardingRoute.NeedsAuth -> AuthFlow(
            coordinator = coordinator,
            appleHandler = appleHandler,
            googleHandler = googleHandler,
            activity = activity,
            isBusy = state.isBusy,
            pendingEmail = state.pendingEmailOtpEmail,
            errorMessage = state.errorMessage,
        )
        OnboardingRoute.CreateTeam -> CreateTeamScreen(
            isBusy = state.isBusy,
            errorMessage = state.errorMessage,
            onCreate = { name -> coordinator.launch { coordinator.createTeam(name) } },
        )
        OnboardingRoute.Ready -> {
            val team = state.currentContext?.team
            val actorId = state.currentContext?.memberActorId
            if (team == null || actorId == null) {
                LobsterSplashScreen()
            } else {
                ReadyFlow(
                    coordinator = coordinator,
                    teamId = team.id,
                    teamName = team.name,
                    currentActorId = actorId,
                    sessionListStoreFactory = sessionListStoreFactory,
                    sessionDetailStoreFactory = sessionDetailStoreFactory,
                )
            }
        }
    }
}

@Composable
private fun ReadyFlow(
    coordinator: OnboardingCoordinator,
    teamId: String,
    teamName: String,
    currentActorId: String,
    sessionListStoreFactory: (teamId: String) -> SessionListStore,
    sessionDetailStoreFactory: (teamId: String, sessionId: String, currentActorId: String) -> SessionDetailStore,
) {
    var openSession by remember { mutableStateOf<SessionRecord?>(null) }
    val listStore = remember(teamId) { sessionListStoreFactory(teamId) }
    val listState by listStore.state.collectAsStateWithLifecycle()
    LaunchedEffect(teamId) { listStore.reload() }

    val active = openSession
    if (active == null) {
        SessionListScreen(
            teamName = teamName,
            sessions = listState.sessions,
            isLoading = listState.isLoading,
            errorMessage = listState.errorMessage,
            onRefresh = { coordinator.launch { listStore.reload() } },
            onSessionClick = { openSession = it },
            onSignOut = { coordinator.launch { coordinator.signOut() } },
        )
    } else {
        val detailStore = remember(active.id) {
            sessionDetailStoreFactory(teamId, active.id, currentActorId)
        }
        val detailState by detailStore.state.collectAsStateWithLifecycle()
        LaunchedEffect(active.id) { detailStore.reload() }
        SessionDetailScreen(
            title = active.title.ifBlank { "Session" },
            currentActorId = currentActorId,
            messages = detailState.messages,
            isLoading = detailState.isLoading,
            isSending = detailState.isSending,
            errorMessage = detailState.errorMessage,
            onSend = { text -> coordinator.launch { detailStore.send(text) } },
            onBack = { openSession = null },
        )
    }
}

@Composable
private fun AuthFlow(
    coordinator: OnboardingCoordinator,
    appleHandler: AppleSignInHandler,
    googleHandler: GoogleSignInHandler,
    activity: ComponentActivity,
    isBusy: Boolean,
    pendingEmail: String?,
    errorMessage: String?,
) {
    val navController = rememberNavController()
    var showInviteSheet by remember { mutableStateOf(false) }

    NavHost(navController, startDestination = "welcome") {
        composable("welcome") {
            WelcomeScreen(
                errorMessage = errorMessage,
                onGetStarted = { navController.navigate("choose") },
            )
        }
        composable("choose") {
            ChooseAuthScreen(
                isBusy = isBusy,
                errorMessage = errorMessage,
                onCreatePrivateWorkspace = { coordinator.launch { coordinator.signInAnonymously() } },
                onSignInOrRegister = { navController.navigate("login") },
                onJoinTeam = { showInviteSheet = true },
            )
        }
        composable("login") {
            LoginScreen(
                pendingEmail = pendingEmail,
                isBusy = isBusy,
                errorMessage = errorMessage,
                onSendCode = { email -> coordinator.launch { coordinator.sendEmailOtp(email) } },
                onVerifyCode = { email, code -> coordinator.launch { coordinator.verifyOtp(email, code) } },
                onUseDifferentEmail = { coordinator.resetPendingEmailOtp() },
                onSignInWithApple = {
                    coordinator.launch {
                        runCatching {
                            val cred = appleHandler.request(activity)
                            coordinator.signInWithAppleCredential(cred.idToken, cred.nonce)
                        }
                    }
                },
                onSignInWithGoogle = {
                    coordinator.launch {
                        runCatching {
                            val cred = googleHandler.request(activity)
                            coordinator.signInWithAppleCredential(cred.idToken, nonce = "")
                        }
                    }
                },
            )
        }
    }

    if (showInviteSheet) {
        InviteJoinSheet(
            isBusy = isBusy,
            errorMessage = errorMessage,
            onDismiss = { showInviteSheet = false },
            onSubmit = { token ->
                coordinator.launch {
                    coordinator.claimInviteSmart(token)
                    showInviteSheet = false
                }
            },
        )
    }
}
