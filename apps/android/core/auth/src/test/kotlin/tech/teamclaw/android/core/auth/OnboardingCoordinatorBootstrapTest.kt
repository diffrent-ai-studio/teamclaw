package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.auth.FakeOnboardingStore.Companion.sampleTeam
import tech.teamclaw.android.core.model.AppBootstrap

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingCoordinatorBootstrapTest {

    @Test fun `bootstrap with no session lands on NeedsAuth`() = runTest {
        val store = FakeOnboardingStore().apply { sessionExists = false }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.NeedsAuth)
        assertThat(coord.state.value.currentContext).isNull()
        assertThat(coord.state.value.isAnonymous).isFalse()
    }

    @Test fun `bootstrap with session + team lands on Ready`() = runTest {
        val team = sampleTeam(id = "T1")
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            bootstrapResult = AppBootstrap(
                memberActorId = "actor-1",
                teams = listOf(team),
                memberActorIdByTeam = mapOf("T1" to "actor-1"),
            )
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        val state = coord.state.value
        assertThat(state.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(state.currentContext?.team?.id).isEqualTo("T1")
        assertThat(state.currentContext?.memberActorId).isEqualTo("actor-1")
    }

    @Test fun `bootstrap with session + no team auto-creates team and lands on Ready`() = runTest {
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            bootstrapResult = AppBootstrap(memberActorId = null, teams = emptyList())
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        assertThat(store.callNames()).contains("createTeam")
        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(coord.state.value.pendingCreatedTeam).isNotNull()
    }

    @Test fun `bootstrap with preferred team honors the preference`() = runTest {
        val t1 = sampleTeam(id = "T1")
        val t2 = sampleTeam(id = "T2", name = "Other")
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            bootstrapResult = AppBootstrap(
                memberActorId = "a1",
                teams = listOf(t1, t2),
                memberActorIdByTeam = mapOf("T1" to "a1", "T2" to "a2"),
            )
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.bootstrap(preferringTeamId = "T2")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.currentContext?.team?.id).isEqualTo("T2")
        assertThat(coord.state.value.currentContext?.memberActorId).isEqualTo("a2")
    }

    @Test fun `bootstrap on store failure lands on Failed with errorMessage`() = runTest {
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            bootstrapError = RuntimeException("boom")
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Failed)
        assertThat(coord.state.value.errorMessage).contains("boom")
    }
}
