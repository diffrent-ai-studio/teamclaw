import { invoke } from "@tauri-apps/api/core";

export type ChannelPlatform =
  | "discord"
  | "wecom"
  | "feishu"
  | "kook"
  | "wechat"
  | "email";

export interface ChannelStatus {
  platform: ChannelPlatform;
  enabled: boolean;
  connected: boolean;
  lastError: string | null;
}

export async function listChannels(): Promise<ChannelStatus[]> {
  try {
    return await invoke<ChannelStatus[]>("list_channels");
  } catch (e) {
    if (isUnreachableError(e)) throw new AmuxdUnreachableError();
    throw e;
  }
}

export async function saveChannelConfig(
  platform: ChannelPlatform,
  config: object,
): Promise<void> {
  try {
    await invoke("save_channel_config", {
      platform,
      configJson: JSON.stringify(config),
    });
  } catch (e) {
    if (isUnreachableError(e)) throw new AmuxdUnreachableError();
    throw e;
  }
}

export async function reloadChannels(): Promise<void> {
  try {
    await invoke("reload_channels");
  } catch (e) {
    if (isUnreachableError(e)) throw new AmuxdUnreachableError();
    throw e;
  }
}

export class AmuxdUnreachableError extends Error {
  constructor() {
    super("amuxd unreachable");
    this.name = "AmuxdUnreachableError";
  }
}

function isUnreachableError(e: unknown): boolean {
  if (e instanceof Error) return /amuxd not reachable/i.test(e.message);
  if (typeof e === "string") return /amuxd not reachable/i.test(e);
  return false;
}
