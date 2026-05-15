package tech.teamclaw.android.core.model

import kotlinx.serialization.Serializable

@Serializable
data class MessageRecord(
    val id: String,
    val sessionId: String,
    val senderActorId: String,
    /** "text", "system", "work_event", etc. */
    val kind: String,
    val content: String,
    /** Unix-epoch millis. */
    val createdAtMs: Long,
    /** Optional model id from messages.metadata. */
    val model: String?,
    /** Daemon-assigned ACP turn correlation, same across rows in one turn. */
    val turnId: String?,
)
