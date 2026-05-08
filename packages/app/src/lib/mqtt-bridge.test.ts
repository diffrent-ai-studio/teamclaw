import { describe, it, expect, vi, beforeEach } from "vitest";

const invokeMock = vi.fn();
const listenMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: invokeMock }));
vi.mock("@tauri-apps/api/event", () => ({ listen: listenMock }));

const { mqttConnect, mqttSubscribe, mqttPublish, listenForEnvelopes } = await import("./mqtt-bridge");

beforeEach(() => {
  invokeMock.mockReset();
  listenMock.mockReset();
});

describe("mqtt-bridge", () => {
  it("mqttConnect forwards args", async () => {
    invokeMock.mockResolvedValueOnce(undefined);
    await mqttConnect({
      brokerHost: "h", brokerPort: 1883, username: "u", password: "p",
      clientId: "c", teamId: "t",
    });
    expect(invokeMock).toHaveBeenCalledWith("mqtt_connect", {
      brokerHost: "h", brokerPort: 1883, username: "u", password: "p",
      clientId: "c", teamId: "t",
    });
  });

  it("mqttSubscribe forwards topic", async () => {
    invokeMock.mockResolvedValueOnce(undefined);
    await mqttSubscribe("amux/t1/session/s1/live");
    expect(invokeMock).toHaveBeenCalledWith("mqtt_subscribe", { topic: "amux/t1/session/s1/live" });
  });

  it("mqttPublish converts Uint8Array to array", async () => {
    invokeMock.mockResolvedValueOnce(undefined);
    await mqttPublish("topic", new Uint8Array([1, 2, 3]));
    expect(invokeMock).toHaveBeenCalledWith("mqtt_publish", {
      topic: "topic", bytes: [1, 2, 3], retain: false,
    });
  });

  it("listenForEnvelopes wires Tauri listen", async () => {
    listenMock.mockImplementation(async (_event, _cb) => () => {});
    const unlisten = await listenForEnvelopes(() => {});
    expect(typeof unlisten).toBe("function");
    expect(listenMock).toHaveBeenCalledWith("mqtt:envelope", expect.any(Function));
  });
});
