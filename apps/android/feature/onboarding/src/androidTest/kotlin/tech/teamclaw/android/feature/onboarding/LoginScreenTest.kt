package tech.teamclaw.android.feature.onboarding

import androidx.compose.ui.test.assertExists
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import tech.teamclaw.android.core.design.TeamclawTheme

class LoginScreenTest {
    @get:Rule val rule = createComposeRule()

    @Test fun emailEntryEnablesSendCode() {
        var captured: String? = null
        rule.setContent {
            TeamclawTheme {
                LoginScreen(
                    pendingEmail = null, isBusy = false, errorMessage = null,
                    onSendCode = { captured = it },
                    onVerifyCode = { _, _ -> },
                    onUseDifferentEmail = {},
                    onSignInWithApple = {},
                    onSignInWithGoogle = {},
                )
            }
        }
        rule.onNodeWithTag("login.emailField").performTextInput("foo@bar.com")
        rule.onNodeWithTag("login.submitButton").performClick()
        assertEquals("foo@bar.com", captured)
    }

    @Test fun codeFieldVisibleWhenPending() {
        rule.setContent {
            TeamclawTheme {
                LoginScreen(
                    pendingEmail = "foo@bar.com", isBusy = false, errorMessage = null,
                    onSendCode = {}, onVerifyCode = { _, _ -> },
                    onUseDifferentEmail = {}, onSignInWithApple = {}, onSignInWithGoogle = {},
                )
            }
        }
        rule.onNodeWithTag("login.codeField").assertExists()
    }
}
