package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme
import tech.teamclaw.android.feature.onboarding.components.RoleCardsIllustration

@Composable
fun WelcomeScreen(
    errorMessage: String?,
    onGetStarted: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Hai.Mist).padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            RoleCardsIllustration()
            Text("Teamclaw", style = MaterialTheme.typography.displayLarge, color = Hai.Onyx)
            Text(
                "AI digital employees\nfor every role.",
                style = MaterialTheme.typography.bodyLarge,
                color = Hai.Basalt,
                textAlign = TextAlign.Center,
            )
            Text("Your Ally. Together.", style = MaterialTheme.typography.bodySmall, color = Hai.Slate)
        }
        Spacer(Modifier.weight(1f))

        if (!errorMessage.isNullOrEmpty()) {
            Box(
                Modifier.fillMaxWidth().padding(bottom = 8.dp).clip(RoundedCornerShape(10.dp))
                    .background(Hai.Pebble).padding(12.dp),
            ) {
                Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
            }
        }

        Button(
            onClick = onGetStarted,
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 48.dp)
                .testTag("welcome.getStartedButton")
                .semantics { contentDescription = "welcome.getStartedButton" },
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
        ) {
            Text("Get Started", style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Preview
@Composable
private fun WelcomePreview() {
    TeamclawTheme { WelcomeScreen(errorMessage = null, onGetStarted = {}) }
}
