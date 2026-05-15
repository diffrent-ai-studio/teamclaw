package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.model.InviteCreateInput
import tech.teamclaw.android.core.model.InviteCreated
import tech.teamclaw.android.core.model.InviteKind
import tech.teamclaw.android.core.model.TeamRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InviteMemberSheet(
    isInviting: Boolean,
    errorMessage: String?,
    lastInvite: InviteCreated?,
    onDismiss: () -> Unit,
    onSubmit: (InviteCreateInput) -> Unit,
    onClearLastInvite: () -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var displayName by remember { mutableStateOf("") }
    var agentKind by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf(InviteKind.MEMBER) }
    val clipboard: ClipboardManager = LocalClipboardManager.current

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                if (kind == InviteKind.MEMBER) "Invite a teammate" else "Invite an agent",
                style = MaterialTheme.typography.titleLarge,
            )

            if (lastInvite == null) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = kind == InviteKind.MEMBER,
                        onClick = { kind = InviteKind.MEMBER },
                        shape = SegmentedButtonDefaults.itemShape(0, 2),
                    ) { Text("Member") }
                    SegmentedButton(
                        selected = kind == InviteKind.AGENT,
                        onClick = { kind = InviteKind.AGENT },
                        shape = SegmentedButtonDefaults.itemShape(1, 2),
                    ) { Text("Agent") }
                }

                OutlinedTextField(
                    value = displayName, onValueChange = { displayName = it },
                    label = { Text(if (kind == InviteKind.MEMBER) "Display name" else "Agent name") },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    singleLine = true,
                )

                if (kind == InviteKind.AGENT) {
                    OutlinedTextField(
                        value = agentKind, onValueChange = { agentKind = it },
                        label = { Text("Agent kind (e.g. codex, claude)") },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        singleLine = true,
                    )
                }

                if (!errorMessage.isNullOrEmpty()) {
                    Box(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                            .background(Hai.Cinnabar.copy(alpha = 0.10f)).padding(10.dp),
                    ) {
                        Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
                    }
                }

                val canSubmit = !isInviting && displayName.isNotBlank() &&
                    (kind == InviteKind.MEMBER || agentKind.isNotBlank())

                Button(
                    onClick = {
                        onSubmit(
                            InviteCreateInput(
                                kind = kind,
                                displayName = displayName,
                                teamRole = if (kind == InviteKind.MEMBER) TeamRole.MEMBER else null,
                                agentKind = if (kind == InviteKind.AGENT) agentKind.trim() else null,
                            )
                        )
                    },
                    enabled = canSubmit,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
                ) {
                    Text(if (isInviting) "Creating…" else "Create invite link")
                }
            } else {
                Text(
                    "Share this link with your teammate. It expires in ~7 days.",
                    style = MaterialTheme.typography.bodyMedium, color = Hai.Basalt,
                )
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(Hai.Pebble).padding(12.dp),
                ) {
                    Text(
                        lastInvite.deeplink,
                        style = MaterialTheme.typography.bodySmall,
                        color = Hai.Onyx,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { clipboard.setText(AnnotatedString(lastInvite.deeplink)) },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(18.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
                    ) { Text("Copy link") }
                    TextButton(onClick = {
                        onClearLastInvite()
                        displayName = ""
                    }) { Text("Create another", color = Hai.Cinnabar) }
                }
            }

            Spacer(Modifier.padding(bottom = 8.dp))
        }
    }
}
