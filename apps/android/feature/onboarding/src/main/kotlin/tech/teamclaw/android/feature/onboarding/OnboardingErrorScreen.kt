package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme

@Composable
fun OnboardingErrorScreen(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Hai.Mist).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Setup Failed", style = MaterialTheme.typography.titleLarge, color = Hai.Onyx)
        Text(message, style = MaterialTheme.typography.bodyLarge, color = Hai.Basalt)
        Button(onClick = onRetry, modifier = Modifier.padding(top = 48.dp)) {
            Text("Retry")
        }
    }
}

@Preview
@Composable
private fun OnboardingErrorPreview() {
    TeamclawTheme { OnboardingErrorScreen("Network unreachable", {}) }
}
