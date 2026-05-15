package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme

@Composable
fun ChooseAuthScreen(
    isBusy: Boolean,
    errorMessage: String?,
    onCreatePrivateWorkspace: () -> Unit,
    onSignInOrRegister: () -> Unit,
    onJoinTeam: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Hai.Mist).padding(bottom = 32.dp),
    ) {
        Column(
            modifier = Modifier.padding(top = 58.dp, start = 28.dp, end = 28.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Set up Teamclaw", style = MaterialTheme.typography.headlineMedium, color = Hai.Onyx)
            Text(
                "Create your workspace or join the team that already works with your AI allies.",
                style = MaterialTheme.typography.bodyLarge, color = Hai.Basalt,
            )
        }
        Spacer(Modifier.weight(1f))

        Column(
            modifier = Modifier.padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ActionRow(
                title = "Create a private workspace",
                caption = "Start with an AI digital employee. No email needed.",
                isPrimary = true,
                enabled = !isBusy,
                onClick = onCreatePrivateWorkspace,
                testTag = "choose.anonymousButton",
            )
            ActionRow(
                title = "Sign in or register",
                caption = "Use email, Apple, or Google to sync across devices.",
                isPrimary = false,
                enabled = !isBusy,
                onClick = onSignInOrRegister,
                testTag = "choose.signInButton",
            )
            ActionRow(
                title = "Join a team",
                caption = "Paste an invite link from a teammate.",
                isPrimary = false,
                enabled = !isBusy,
                onClick = onJoinTeam,
                testTag = "choose.joinTeamButton",
            )
        }

        if (!errorMessage.isNullOrEmpty()) {
            Text(
                errorMessage,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 12.dp),
                style = MaterialTheme.typography.bodySmall, color = Hai.CinnabarDeep,
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun ActionRow(
    title: String,
    caption: String,
    isPrimary: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    testTag: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(if (isPrimary) Hai.Paper else Hai.Paper.copy(alpha = 0.76f))
            .border(
                width = 1.dp,
                color = if (isPrimary) Hai.Cinnabar.copy(alpha = 0.22f) else Hai.Hairline,
                shape = RoundedCornerShape(18.dp),
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(14.dp)
            .testTag(testTag)
            .semantics { contentDescription = testTag },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(if (isPrimary) Hai.Cinnabar else Hai.Pebble),
        )
        Spacer(Modifier.size(13.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = Hai.Onyx)
            Text(caption, style = MaterialTheme.typography.bodySmall, color = Hai.Basalt)
        }
    }
}

@Preview
@Composable
private fun ChooseAuthPreview() {
    TeamclawTheme { ChooseAuthScreen(false, null, {}, {}, {}) }
}
