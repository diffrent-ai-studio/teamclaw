package tech.teamclaw.android.core.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import tech.teamclaw.android.core.model.MessageRecord

/**
 * Per-session message timeline. PostgREST-seeded; no MQTT yet (P3+).
 * Single source of truth for the session detail screen.
 */
class SessionDetailStore(
    private val teamId: String,
    private val sessionId: String,
    private val currentActorId: String,
    private val repository: MessagesRepository,
) {
    data class UiState(
        val messages: List<MessageRecord> = emptyList(),
        val isLoading: Boolean = false,
        val isSending: Boolean = false,
        val errorMessage: String? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    suspend fun reload() {
        if (_state.value.isLoading) return
        _state.update { it.copy(isLoading = true, errorMessage = null) }
        try {
            val rows = repository.listMessages(sessionId)
            _state.update { it.copy(messages = rows, isLoading = false) }
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isLoading = false) }
        }
    }

    suspend fun send(content: String) {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) return
        if (_state.value.isSending) return
        _state.update { it.copy(isSending = true, errorMessage = null) }
        try {
            val inserted = repository.insertUserMessage(
                teamId = teamId,
                sessionId = sessionId,
                senderActorId = currentActorId,
                content = trimmed,
            )
            _state.update { it.copy(messages = it.messages + inserted, isSending = false) }
        } catch (t: Throwable) {
            _state.update { it.copy(errorMessage = t.message, isSending = false) }
        }
    }
}
