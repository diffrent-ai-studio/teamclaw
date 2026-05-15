package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.model.AppBootstrap

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingCoordinatorEmailOtpTest {

    @Test fun `sendEmailOtp stores pendingEmail on success`() = runTest {
        val store = FakeOnboardingStore()
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.sendEmailOtp("foo@example.com")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.pendingEmailOtpEmail).isEqualTo("foo@example.com")
        assertThat(coord.state.value.errorMessage).isNull()
    }

    @Test fun `sendEmailOtp surfaces error without storing pendingEmail`() = runTest {
        val store = FakeOnboardingStore().apply {
            sendOtpError = RuntimeException("rate-limited")
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.sendEmailOtp("foo@example.com")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.pendingEmailOtpEmail).isNull()
        assertThat(coord.state.value.errorMessage).contains("rate-limited")
    }

    @Test fun `verifyOtp success triggers bootstrap and lands on Ready`() = runTest {
        val team = FakeOnboardingStore.sampleTeam()
        val store = FakeOnboardingStore().apply {
            bootstrapResult = AppBootstrap(
                memberActorId = "a1",
                teams = listOf(team),
                memberActorIdByTeam = mapOf(team.id to "a1"),
            )
        }
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))

        coord.verifyOtp("foo@example.com", "12345678")
        testScheduler.advanceUntilIdle()

        assertThat(coord.state.value.route).isEqualTo(OnboardingRoute.Ready)
        assertThat(store.callNames()).containsAtLeast("verifyOtp", "loadBootstrap")
    }

    @Test fun `resetPendingEmailOtp clears email and error`() = runTest {
        val store = FakeOnboardingStore()
        val coord = OnboardingCoordinator(store, dispatcher = StandardTestDispatcher(testScheduler))
        coord.sendEmailOtp("a@b.c")
        testScheduler.advanceUntilIdle()

        coord.resetPendingEmailOtp()

        assertThat(coord.state.value.pendingEmailOtpEmail).isNull()
        assertThat(coord.state.value.errorMessage).isNull()
    }
}
