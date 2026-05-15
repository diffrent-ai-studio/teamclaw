package tech.teamclaw.android.feature.onboarding

import androidx.compose.ui.test.assertExists
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import tech.teamclaw.android.core.design.TeamclawTheme

class ChooseAuthScreenTest {
    @get:Rule val rule = createComposeRule()

    @Test fun threeButtonsRender() {
        rule.setContent {
            TeamclawTheme { ChooseAuthScreen(false, null, {}, {}, {}) }
        }
        rule.onNodeWithTag("choose.anonymousButton").assertExists()
        rule.onNodeWithTag("choose.signInButton").assertExists()
        rule.onNodeWithTag("choose.joinTeamButton").assertExists()
    }

    @Test fun anonymousClickCallback() {
        var clicked = false
        rule.setContent {
            TeamclawTheme {
                ChooseAuthScreen(false, null, { clicked = true }, {}, {})
            }
        }
        rule.onNodeWithTag("choose.anonymousButton").performClick()
        assertTrue(clicked)
    }
}
