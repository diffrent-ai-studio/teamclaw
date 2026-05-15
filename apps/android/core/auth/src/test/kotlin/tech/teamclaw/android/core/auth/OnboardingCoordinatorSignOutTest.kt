package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.model.AppBootstrap

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingCoordinatorSignOutTest {

    @Test fun `signOut clears context and lands on NeedsAuth`() = runTest {
        val team = FakeOnboardingStore.sampleTeam()
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            bootstrapResult = AppBootstrap(
                memberActorId = "a", teams = listOf(team),
                memberActorIdByTeam = mapOf(team.id to "a"),
            )
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))
        coord.bootstrap(); testScheduler.advanceUntilIdle()
        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)

        coord.signOut(); testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.NeedsAuth)
        assertThat(coord.state.value.currentContext).isNull()
        assertThat(coord.state.value.pendingCreatedTeam).isNull()
        assertThat(coord.state.value.pendingEmailOtpEmail).isNull()
        assertThat(coord.state.value.isAnonymous).isFalse()
    }
}
