import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";
import { deflateSync } from "node:zlib";
import type { Snapshot } from "../shared";
import { engineError } from "../core/engine-error";
export class WhisperWorker {
  private child?: ChildProcessWithoutNullStreams;
  private pending?: {
    resolve: (value: any) => void;
    reject: (reason: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  };
  ready = false;
  gpu: Snapshot["gpu"] = null;
  failure?: Error;
  constructor(
    private binary: string,
    private changed: () => void,
  ) {}
  private response(timeout: number): Promise<any> {
    if (this.pending) throw new Error("worker_busy");
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.stop(new Error(this.ready ? "gpu_inference" : "gpu_init"));
      }, timeout);
      this.pending = { resolve, reject, timer };
    });
  }
  async load(path: string, language = "en", customWords: string[] = []) {
    this.stop();
    const result = this.response(120000);
    const child = (this.child = spawn(this.binary, [path, language], {
      stdio: "pipe",
      windowsHide: true,
      shell: false,
    }));
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => {
      if (this.child !== child) return;
      const pending = this.pending;
      this.pending = undefined;
      if (!pending) {
        this.stop();
        return;
      }
      clearTimeout(pending.timer);
      try {
        if (line.length > 65536) throw new Error("worker_protocol");
        const value = JSON.parse(line);
        if (value.error) {
          const error = new Error(String(value.error));
          throw engineError(error) ? error : new Error("worker_failure");
        }
        pending.resolve(value);
      } catch (reason) {
        const error = engineError(reason)
          ? (reason as Error)
          : new Error("worker_protocol");
        pending.reject(error);
        this.stop(error);
      }
    });
    child.stderr.resume(); // Native diagnostics are never forwarded or retained.
    child.on("error", () => {
      if (this.child === child) this.stop(new Error("gpu_init"));
    });
    child.on("exit", () => {
      if (this.child === child)
        this.stop(new Error(this.ready ? "gpu_inference" : "gpu_init"));
      lines.close();
    });
    child.stdin.on("error", () => {
      if (this.child === child)
        this.stop(new Error(this.ready ? "gpu_inference" : "gpu_init"));
    });
    const prompt = Buffer.from(customWords.join(", "));
    const header = Buffer.alloc(4);
    header.writeUInt32LE(prompt.length);
    child.stdin.write(header);
    child.stdin.write(prompt, () => prompt.fill(0));
    const value = await result;
    if (value.ready !== true || this.child !== child)
      throw new Error("worker_load");
    if (
      !value.gpu ||
      !["Metal", "Vulkan"].includes(value.gpu.backend) ||
      typeof value.gpu.device !== "string" ||
      !value.gpu.device.trim() ||
      value.gpu.device.length > 256
    ) {
      const error = new Error("gpu_unavailable");
      this.stop(error);
      throw error;
    }
    this.gpu = { backend: value.gpu.backend, device: value.gpu.device };
    this.ready = true;
    this.changed();
  }
  async transcribe(samples: Float32Array): Promise<string | null> {
    if (
      !this.ready ||
      !this.child ||
      !samples.length ||
      samples.length > 480000
    )
      throw new Error("worker_not_ready");
    const result = this.response(300000);
    const header = Buffer.alloc(4);
    header.writeUInt32LE(samples.length);
    const audio = Buffer.alloc(samples.length * 4);
    for (let i = 0; i < samples.length; i++)
      audio.writeFloatLE(samples[i], i * 4);
    this.child.stdin.write(header);
    this.child.stdin.write(audio, () => audio.fill(0));
    const value = await result;
    if (
      typeof value.text !== "string" ||
      !Number.isFinite(value.noSpeechProbability) ||
      !Number.isFinite(value.averageLogProbability)
    )
      throw new Error("worker_protocol");
    const bytes = Buffer.from(value.text);
    const ratio = bytes.length / Math.max(1, deflateSync(bytes).length);
    if (
      value.noSpeechProbability > 0.6 ||
      value.averageLogProbability < -1 ||
      ratio > 2.4 ||
      /thanks for watching/i.test(value.text)
    )
      return null;
    return value.text;
  }
  stop(error?: Error) {
    const child = this.child;
    this.child = undefined;
    this.ready = false;
    this.gpu = null;
    this.failure = error;
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(error ?? new Error("worker_stopped"));
      this.pending = undefined;
    }
    child?.stdin.destroy();
    child?.kill();
    this.changed();
  }
}
