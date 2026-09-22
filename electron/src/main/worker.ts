import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";
import { deflateSync } from "node:zlib";
export class WhisperWorker {
  private child?: ChildProcessWithoutNullStreams;
  private pending?: {
    resolve: (value: any) => void;
    reject: (reason: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  };
  ready = false;
  constructor(
    private binary: string,
    private changed: () => void,
  ) {}
  private response(timeout: number): Promise<any> {
    if (this.pending) throw new Error("worker_busy");
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.stop();
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
        if (value.error) throw new Error("worker_failure");
        pending.resolve(value);
      } catch {
        pending.reject(new Error("worker_protocol"));
        this.stop();
      }
    });
    child.stderr.resume(); // Native diagnostics are never forwarded or retained.
    child.on("error", () => {
      if (this.child === child) this.stop();
    });
    child.on("exit", () => {
      if (this.child === child) this.stop();
      lines.close();
    });
    child.stdin.on("error", () => {
      if (this.child === child) this.stop();
    });
    const prompt = Buffer.from(customWords.join(", "));
    const header = Buffer.alloc(4);
    header.writeUInt32LE(prompt.length);
    child.stdin.write(header);
    child.stdin.write(prompt, () => prompt.fill(0));
    const value = await result;
    if (value.ready !== true || this.child !== child)
      throw new Error("worker_load");
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
  stop() {
    const child = this.child;
    this.child = undefined;
    this.ready = false;
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(new Error("worker_stopped"));
      this.pending = undefined;
    }
    child?.stdin.destroy();
    child?.kill();
    this.changed();
  }
}
