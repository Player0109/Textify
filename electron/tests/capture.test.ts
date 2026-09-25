import type { BrowserWindow } from "electron";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Capture } from "../src/main/capture";

afterEach(() => vi.useRealTimers());
describe("microphone IPC lifecycle", () => {
  function setup() {
    const send = vi.fn(),
      samples = vi.fn(),
      failed = vi.fn();
    const capture = new Capture({
      webContents: { send },
      isDestroyed: () => false,
    } as unknown as BrowserWindow);
    return { capture, send, samples, failed };
  }
  it("accepts only bounded float frames from the active session", async () => {
    const { capture, samples, failed } = setup();
    const start = capture.start(1, "default", samples, failed);
    capture.receive({ id: 1, kind: "started" });
    await start;
    capture.receive({
      id: 2,
      kind: "samples",
      samples: new Float32Array(320).buffer,
    });
    capture.receive({
      id: 1,
      kind: "samples",
      samples: new Float32Array(321).buffer,
    });
    capture.receive({ id: 1, kind: "samples", samples: new ArrayBuffer(3) });
    expect(samples).not.toHaveBeenCalled();
    capture.receive({
      id: 1,
      kind: "samples",
      samples: new Float32Array(320).buffer,
    });
    expect(samples).toHaveBeenCalledOnce();
    capture.shutdown();
  });
  it("drains a pending start on shutdown", async () => {
    const { capture, samples, failed } = setup();
    const start = capture.start(1, "default", samples, failed);
    capture.shutdown();
    await expect(start).rejects.toThrow("audio_shutdown");
    capture.receive({ id: 1, kind: "started" });
    capture.receive({
      id: 1,
      kind: "samples",
      samples: new Float32Array(320).buffer,
    });
    expect(samples).not.toHaveBeenCalled();
  });
  it("discards a start when the renderer never acknowledges it", async () => {
    vi.useFakeTimers();
    const { capture, send, samples, failed } = setup();
    const outcome = expect(
      capture.start(1, "default", samples, failed),
    ).rejects.toThrow("audio_timeout");
    await vi.advanceTimersByTimeAsync(30000);
    await outcome;
    expect(send).toHaveBeenLastCalledWith("audio-command", {
      id: 1,
      action: "discard",
    });
    capture.shutdown();
  });
  it("reports device loss for the active session only", async () => {
    const { capture, samples, failed } = setup();
    const start = capture.start(1, "default", samples, failed);
    capture.receive({ id: 1, kind: "started" });
    await start;
    capture.receive({ id: 2, kind: "error" });
    expect(failed).not.toHaveBeenCalled();
    capture.receive({ id: 1, kind: "error" });
    expect(failed).toHaveBeenCalledOnce();
    capture.shutdown();
  });
});
