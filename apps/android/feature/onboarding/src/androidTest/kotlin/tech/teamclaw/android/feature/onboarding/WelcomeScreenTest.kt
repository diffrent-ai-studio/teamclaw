package tech.teamclaw.android.feature.onboarding

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import tech.teamclaw.android.core.design.TeamclawTheme

class WelcomeScreenTest {
    @get:Rule val rule = createComposeRule()

    @Test fun headlineAndCtaRender() {
        var clicked = false
        rule.setContent {
            TeamclawTheme {
                WelcomeScreen(errorMessage = null, onGetStarted = { clicked = true })
            }
        }
        rule.onNodeWithText("Teamclaw").assertIsDisplayed()
        rule.onNodeWithTag("welcome.getStartedButton").assertIsDisplayed().performClick()
        assertTrue(clicked)
    }
}
