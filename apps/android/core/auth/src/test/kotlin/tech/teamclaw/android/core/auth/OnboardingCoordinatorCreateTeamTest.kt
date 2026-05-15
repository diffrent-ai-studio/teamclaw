package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingCoordinatorCreateTeamTest {

    @Test fun `createTeam with blank name surfaces error and stays on CreateTeam`() = runTest {
        val store = FakeOnboardingStore()
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.createTeam("   ")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.CreateTeam)
        assertThat(coord.state.value.errorMessage).contains("required")
    }

    @Test fun `createTeam happy path stores pendingCreatedTeam + Ready`() = runTest {
        val store = FakeOnboardingStore()
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.createTeam("My Team")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(coord.state.value.pendingCreatedTeam).isNotNull()
        assertThat(coord.state.value.currentContext?.team?.name).isNotEmpty()
    }
}
