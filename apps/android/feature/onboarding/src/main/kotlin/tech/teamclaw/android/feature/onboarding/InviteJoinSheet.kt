package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.deeplink.DeepLinkParser
import tech.teamclaw.android.core.design.Hai

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InviteJoinSheet(
    isBusy: Boolean,
    errorMessage: String?,
    onDismiss: () -> Unit,
    onSubmit: (token: String) -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var raw by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }
    val parser = remember { DeepLinkParser() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Join with invite link", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Paste the link your teammate shared. Teamclaw will sign you in and add you to their team.",
                    style = MaterialTheme.typography.bodyMedium, color = Hai.Basalt,
                )
            }

            OutlinedTextField(
                value = raw,
                onValueChange = {
                    raw = it
                    localError = null
                },
                label = { Text("teamclaw://invite?token=… or just the token") },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                singleLine = false,
            )

            val inlineError = localError ?: errorMessage
            if (!inlineError.isNullOrEmpty()) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(Hai.Cinnabar.copy(alpha = 0.10f)).padding(10.dp),
                ) {
                    Text(inlineError, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
                }
            }

            Button(
                onClick = {
                    val token = parser.parseToken(raw)
                    if (token == null) {
                        localError = "Couldn't read a token from that link."
                    } else {
                        onSubmit(token)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
                enabled = !isBusy && raw.isNotBlank(),
            ) {
                Text(if (isBusy) "Joining…" else "Continue")
            }
        }
    }
}
