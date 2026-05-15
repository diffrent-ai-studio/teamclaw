package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.model.AppBootstrap
import tech.teamclaw.android.core.model.ClaimResult

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingCoordinatorClaimInviteTest {

    @Test fun `pending invite token claims before auto-create and prefers claimed team`() = runTest {
        val claimed = FakeOnboardingStore.sampleTeam(id = "T-CLAIMED", name = "Claimed")
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            claimResult = ClaimResult(
                actorId = "a-claim", teamId = "T-CLAIMED",
                actorType = "member", displayName = "X", refreshToken = null,
            )
            bootstrapResult = AppBootstrap(memberActorId = null, teams = emptyList())
        }
        var loadCount = 0
        val wrapped = object : OnboardingStore by store {
            override suspend fun loadBootstrap(): AppBootstrap {
                loadCount++
                return if (loadCount == 1) AppBootstrap(memberActorId = null, teams = emptyList())
                else AppBootstrap(
                    memberActorId = "a-claim",
                    teams = listOf(claimed),
                    memberActorIdByTeam = mapOf("T-CLAIMED" to "a-claim"),
                )
            }
        }
        val coord = OnboardingCoordinator(wrapped, dispatcher = StandardTestDispatcher(testScheduler))
        coord.setPendingInviteToken("INVITE")

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(coord.state.value.currentContext?.team?.id).isEqualTo("T-CLAIMED")
        assertThat(store.callNames()).contains("claimInvite")
        assertThat(store.callNames()).doesNotContain("createTeam")
    }

    @Test fun `claim failure rolls back session and lands on NeedsAuth with error`() = runTest {
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            claimError = RuntimeException("expired token")
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))
        coord.setPendingInviteToken("BAD")

        coord.bootstrap()
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.NeedsAuth)
        assertThat(coord.state.value.errorMessage).contains("expired token")
        assertThat(store.callNames()).contains("signOut")
    }

    @Test fun `claimInviteSmart with refreshToken sets session then bootstraps`() = runTest {
        val team = FakeOnboardingStore.sampleTeam(id = "T-RT")
        val store = FakeOnboardingStore().apply {
            sessionExists = true
            claimResult = ClaimResult(
                actorId = "a", teamId = "T-RT",
                actorType = "agent", displayName = "X", refreshToken = "RT-123",
            )
            bootstrapResult = AppBootstrap(
                memberActorId = "a",
                teams = listOf(team),
                memberActorIdByTeam = mapOf(team.id to "a"),
            )
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.claimInviteSmart("X")
        testScheduler.advanceUntilIdle()

        assertThat(store.callNames()).containsAtLeast("signOut", "claimInvite", "setSession", "loadBootstrap")
        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(coord.state.value.currentContext?.team?.id).isEqualTo("T-RT")
    }
}
