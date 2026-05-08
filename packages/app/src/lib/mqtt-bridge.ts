import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export interface IncomingEnvelope {
  topic: string;
  bytes: number[];
}

export async function mqttConnect(args: {
  brokerHost: string;
  brokerPort: number;
  username: string;
  password: string;
  clientId: string;
  teamId: string;
}): Promise<void> {
  await invoke("mqtt_connect", {
    brokerHost: args.brokerHost,
    brokerPort: args.brokerPort,
    username: args.username,
    password: args.password,
    clientId: args.clientId,
    teamId: args.teamId,
  });
}

export async function mqttSubscribe(topic: string): Promise<void> {
  await invoke("mqtt_subscribe", { topic });
}

export async function mqttPublish(topic: string, bytes: Uint8Array, retain = false): Promise<void> {
  await invoke("mqtt_publish", {
    topic,
    bytes: Array.from(bytes),
    retain,
  });
}

export async function listenForEnvelopes(handler: (env: IncomingEnvelope) => void): Promise<UnlistenFn> {
  return listen<IncomingEnvelope>("mqtt:envelope", (msg) => {
    handler(msg.payload);
  });
}
