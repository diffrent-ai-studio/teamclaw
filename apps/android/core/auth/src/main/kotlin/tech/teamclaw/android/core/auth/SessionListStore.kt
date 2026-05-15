package tech.teamclaw.android.core.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import tech.teamclaw.android.core.model.SessionRecord
import java.util.UUID

class SessionListStore(
    private val teamId: String,
    private val currentActorId: String,
    private val sessionsRepository: SessionsRepository,
    private val messagesRepository: MessagesRepository,
) {
    data class UiState(
        val sessions: List<SessionRecord> = emptyList(),
        val isLoading: Boolean = false,
        val isCreating: Boolean = false,
        val errorMessage: String? = null,
        val justCreatedSessionId: String? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    suspend fun reload() {
        if (_state.value.isLoading) return
        _state.update { it.copy(isLoading = true, errorMessage = null) }
        try {
            val rows = sessionsRepository.listSessions(teamId)
            _state.update { it.copy(sessions = rows, isLoading = false) }
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isLoading = false) }
        }
    }

    /**
     * Create a new session with the picked agent + current actor as
     * participants, then persist the first user message. Mirrors the iOS
     * SessionCreationUseCase steps 1, 3 (Supabase create) + step 4 (first
     * message). Subscribe-live (step 2) and runtime spawns (step 5) are
     * handled outside this store — the MQTT layer auto-subscribes on
     * session-detail open, and agent runtime spawns happen on the daemon
     * side when the message lands.
     */
    suspend fun createSession(
        title: String,
        agentActorId: String,
        firstMessage: String,
    ): SessionRecord? {
        if (_state.value.isCreating) return null
        _state.update { it.copy(isCreating = true, errorMessage = null, justCreatedSessionId = null) }
        return try {
            val id = UUID.randomUUID().toString().lowercase()
            val created = sessionsRepository.createSession(
                SessionCreateInput(
                    id = id,
                    teamId = teamId,
                    createdByActorId = currentActorId,
                    title = title,
                    summary = firstMessage,
                    primaryAgentId = agentActorId,
                    participantActorIds = listOf(currentActorId, agentActorId),
                )
            )
            messagesRepository.insertUserMessage(
                teamId = teamId,
                sessionId = created.id,
                senderActorId = currentActorId,
                content = firstMessage,
                mentionActorIds = listOf(agentActorId),
            )
            _state.update {
                it.copy(
                    sessions = listOf(created) + it.sessions,
                    isCreating = false,
                    justCreatedSessionId = created.id,
                )
            }
            created
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isCreating = false) }
            null
        }
    }

    fun clearJustCreated() {
        _state.update { it.copy(justCreatedSessionId = null) }
    }
}
