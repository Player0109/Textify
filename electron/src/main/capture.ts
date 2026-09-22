import type { BrowserWindow } from "electron";
import type { AudioCommand, AudioReply } from "../shared";
export class Capture {
  private waiting = new Map<
    string,
    {
      resolve(value: AudioReply): void;
      reject(error: Error): void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  private active?: {
    id: number;
    samples(data: Float32Array): void;
    failed(): void;
  };
  devices: { id: string; name: string }[] = [];
  constructor(private window: BrowserWindow) {}
  private command(
    command: AudioCommand,
    reply: AudioReply["kind"],
  ): Promise<AudioReply> {
    const key = `${command.id}:${reply}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiting.delete(key);
        this.window.webContents.send("audio-command", {
          id: command.id,
          action: "discard",
        });
        reject(new Error("audio_timeout"));
      }, 30000);
      this.waiting.set(key, { resolve, reject, timer });
      this.window.webContents.send("audio-command", command);
    });
  }
  receive(reply: AudioReply) {
    if (!reply || !Number.isSafeInteger(reply.id)) return;
    if (reply.kind === "samples") {
      if (
        this.active?.id === reply.id &&
        reply.samples instanceof ArrayBuffer &&
        reply.samples.byteLength <= 1280 &&
        reply.samples.byteLength % 4 === 0
      )
        this.active.samples(new Float32Array(reply.samples));
      return;
    }
    if (reply.kind === "error") {
      for (const [key, pending] of this.waiting)
        if (key.startsWith(`${reply.id}:`)) {
          clearTimeout(pending.timer);
          pending.reject(new Error("audio_failed"));
          this.waiting.delete(key);
        }
      if (this.active?.id === reply.id) this.active.failed();
      return;
    }
    const key = `${reply.id}:${reply.kind}`,
      pending = this.waiting.get(key);
    if (pending) {
      this.waiting.delete(key);
      clearTimeout(pending.timer);
      pending.resolve(reply);
    }
  }
  async start(
    id: number,
    microphone: string,
    samples: (data: Float32Array) => void,
    failed: () => void,
  ) {
    this.active = { id, samples, failed };
    try {
      await this.command({ id, action: "start", microphone }, "started");
    } catch (error) {
      if (this.active?.id === id) this.active = undefined;
      if (!this.window.isDestroyed())
        this.window.webContents.send("audio-command", {
          id,
          action: "discard",
        });
      throw error;
    }
  }
  async stop(id: number, discard: boolean) {
    if (this.active?.id !== id) return;
    if (!discard) await new Promise((resolve) => setTimeout(resolve, 200));
    await this.command({ id, action: discard ? "discard" : "stop" }, "stopped");
    if (this.active?.id === id) this.active = undefined;
  }
  async probe() {
    if (this.active) throw new Error("audio_busy");
    const reply = await this.command(
      { id: -Date.now(), action: "probe" },
      "devices",
    );
    this.devices = reply.devices ?? [];
    return this.devices;
  }
  shutdown() {
    for (const pending of this.waiting.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("audio_shutdown"));
    }
    this.waiting.clear();
    this.active = undefined;
  }
}
