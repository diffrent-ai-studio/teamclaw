package tech.teamclaw.android.core.auth

import tech.teamclaw.android.core.model.AppContext
import tech.teamclaw.android.core.model.CreatedTeam

data class OnboardingState(
    val route: OnboardingRoute = OnboardingRoute.Loading,
    val currentContext: AppContext? = null,
    val pendingCreatedTeam: CreatedTeam? = null,
    val errorMessage: String? = null,
    val pendingEmailOtpEmail: String? = null,
    val isBusy: Boolean = false,
    val isAnonymous: Boolean = false,
    val pendingInviteToken: String? = null,
)
