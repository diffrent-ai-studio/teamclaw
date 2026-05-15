package tech.teamclaw.android.core.auth

sealed interface OnboardingRoute {
    data object Loading    : OnboardingRoute
    data object NeedsAuth  : OnboardingRoute
    data object CreateTeam : OnboardingRoute
    data object Ready      : OnboardingRoute
    data object Failed     : OnboardingRoute
}
