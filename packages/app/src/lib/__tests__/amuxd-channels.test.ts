import { describe, it, expect, vi, beforeEach } from "vitest";
import { listChannels, AmuxdUnreachableError } from "../amuxd-channels";
import * as tauri from "@tauri-apps/api/core";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

describe("amuxd-channels", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("throws AmuxdUnreachableError when invoke rejects with reachability error", async () => {
    vi.mocked(tauri.invoke).mockRejectedValue("amuxd not reachable: foo");
    await expect(listChannels()).rejects.toBeInstanceOf(AmuxdUnreachableError);
  });

  it("returns channel array on success", async () => {
    vi.mocked(tauri.invoke).mockResolvedValue([
      {
        platform: "discord",
        enabled: true,
        connected: false,
        lastError: null,
      },
    ]);
    const result = await listChannels();
    expect(result[0].platform).toBe("discord");
  });
});
