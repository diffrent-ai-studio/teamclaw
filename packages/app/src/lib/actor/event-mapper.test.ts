import { describe, it, expect } from "vitest";
import { envelopeJsonToActorEvent } from "./event-mapper";

const fixture = {
  id: "env_001",
  timestamp: 1715000000.0,
  payload: {
    case: "chatMessage",
    value: {
      actorId: "u_zhangsan",
      text: "hello",
      mentionActorIds: ["agent_claude"],
    },
  },
};

describe("envelopeJsonToActorEvent", () => {
  it("maps a chat_message envelope", () => {
    const ev = envelopeJsonToActorEvent(fixture);
    expect(ev).toEqual({
      kind: "chat_message",
      actorId: "u_zhangsan",
      timestampMs: 1715000000000,
      text: "hello",
      mentionActorIds: ["agent_claude"],
    });
  });

  it("returns null for unknown payload case", () => {
    const ev = envelopeJsonToActorEvent({
      id: "x",
      timestamp: 1,
      payload: { case: "totallyUnknown", value: {} },
    });
    expect(ev).toBeNull();
  });
});
