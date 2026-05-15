package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.model.MessageRecord
import tech.teamclaw.android.core.model.SessionRecord

@OptIn(ExperimentalCoroutinesApi::class)
class SessionListStoreTest {

    private class FakeSessionsRepo(
        var rows: List<SessionRecord> = emptyList(),
        var error: Throwable? = null,
    ) : SessionsRepository {
        var calls = 0
        override suspend fun listSessions(teamId: String): List<SessionRecord> {
            calls++
            error?.let { throw it }
            return rows
        }
        override suspend fun createSession(input: SessionCreateInput): SessionRecord {
            return SessionRecord(
                id = input.id, teamId = input.teamId, ideaId = null,
                createdByActorId = input.createdByActorId,
                primaryAgentId = input.primaryAgentId, mode = input.mode,
                title = input.title, summary = input.summary,
                participantCount = input.participantActorIds.size,
                lastMessagePreview = "", lastMessageAtMs = null, createdAtMs = 0L,
            )
        }
        override suspend fun addParticipants(sessionId: String, actorIds: List<String>) {}
    }

    private class FakeMessagesRepo : MessagesRepository {
        override suspend fun listMessages(sessionId: String, limit: Int): List<MessageRecord> = emptyList()
        override suspend fun insertUserMessage(
            teamId: String, sessionId: String, senderActorId: String,
            content: String, mentionActorIds: List<String>,
        ): MessageRecord = MessageRecord(
            id = "m", sessionId = sessionId, senderActorId = senderActorId,
            kind = "text", content = content, createdAtMs = 0L,
            model = null, turnId = null,
        )
    }

    private fun sample(id: String) = SessionRecord(
        id = id, teamId = "T", ideaId = null, createdByActorId = "a",
        primaryAgentId = null, mode = "chat", title = "Session $id",
        summary = "", participantCount = 1, lastMessagePreview = "",
        lastMessageAtMs = null, createdAtMs = 0L,
    )

    @Test fun `reload populates sessions on success`() = runTest {
        val repo = FakeSessionsRepo(rows = listOf(sample("1"), sample("2")))
        val store = SessionListStore("T", "actor-me", repo, FakeMessagesRepo())

        store.reload()

        assertThat(store.state.value.sessions.map { it.id }).containsExactly("1", "2").inOrder()
        assertThat(store.state.value.isLoading).isFalse()
    }

    @Test fun `reload surfaces error`() = runTest {
        val repo = FakeSessionsRepo(error = RuntimeException("network down"))
        val store = SessionListStore("T", "actor-me", repo, FakeMessagesRepo())

        store.reload()

        assertThat(store.state.value.errorMessage).contains("network down")
    }

    @Test fun `createSession prepends new session and sets justCreated`() = runTest {
        val repo = FakeSessionsRepo()
        val store = SessionListStore("T", "actor-me", repo, FakeMessagesRepo())

        val created = store.createSession(
            title = "Plan migration",
            agentActorId = "agent-1",
            firstMessage = "Let's start",
        )

        assertThat(created).isNotNull()
        assertThat(store.state.value.sessions.first().title).isEqualTo("Plan migration")
        assertThat(store.state.value.justCreatedSessionId).isEqualTo(created!!.id)
    }
}
