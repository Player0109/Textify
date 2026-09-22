import type { Phase, Replacement } from "../shared";
import {
  MAX_SAMPLES,
  rms,
  SpeechGuard,
  stitch,
  trimSilence,
  windows,
} from "./audio";
import { processText } from "./text";
import { engineError } from "./engine-error";

export interface Target {
  target: string;
  secure: boolean;
  appID?: string;
  appName?: string;
  excluded?: boolean;
}
export interface DictationPorts {
  target(): Promise<Target | null>;
  start(
    id: number,
    samples: (data: Float32Array) => void,
    failed: () => void,
  ): Promise<void>;
  stop(id: number, discard: boolean): Promise<void>;
  transcribe(samples: Float32Array): Promise<string | null>;
  insert(
    text: string,
    target: Target,
  ): Promise<"sent" | "skipped" | "unavailable">;
  changed(): void;
}
type Session = {
  id: number;
  started: number;
  ready: boolean;
  cancelled: boolean;
  target: Target | null;
  frames: Float32Array[];
  count: number;
  guard: SpeechGuard;
  startTask: Promise<void>;
};
export class Dictation {
  phase: Phase = "idle";
  message = "";
  level = 0;
  pending = "";
  private serial = 0;
  private copying = false;
  private session?: Session;
  private processingTask?: Promise<void>;
  private activation?: ReturnType<typeof setTimeout>;
  private limit?: ReturnType<typeof setTimeout>;
  constructor(
    private ports: DictationPorts,
    private replacements: () => Replacement[],
    private now = () => Date.now(),
    private language = () => "en",
  ) {}
  get busy() {
    return this.copying || !["idle", "error", "copy"].includes(this.phase);
  }
  get elapsed() {
    return this.session
      ? Math.floor((this.now() - this.session.started) / 1000)
      : 0;
  }
  private update(phase: Phase, message = "") {
    this.phase = phase;
    this.message = message;
    this.ports.changed();
  }
  private timers() {
    clearTimeout(this.activation);
    clearTimeout(this.limit);
  }
  press(manual = false) {
    if (this.busy) return;
    this.pending = "";
    const s: Session = {
      id: ++this.serial,
      started: this.now(),
      ready: false,
      cancelled: false,
      target: null,
      frames: [],
      count: 0,
      guard: new SpeechGuard(),
      startTask: Promise.resolve(),
    };
    this.session = s;
    this.update("armed");
    this.activation = setTimeout(() => {
      if (!s.cancelled && s.ready && this.session === s)
        this.update("recording");
    }, 250);
    s.startTask = (async () => {
      try {
        s.target = manual ? null : await this.ports.target();
        if (s.cancelled) return;
        if (s.target?.secure || s.target?.excluded) {
          s.cancelled = true;
          return;
        }
        await this.ports.start(
          s.id,
          (data) => this.samples(s, data),
          () => {
            void this.cancel("Microphone changed or stopped. Try again.");
          },
        );
        s.ready = true;
        if (s.cancelled) return;
        if (this.now() - s.started >= 250) this.update("recording");
        this.limit = setTimeout(
          () => {
            void this.finish(s);
          },
          Math.max(0, 300000 - (this.now() - s.started)),
        );
      } catch {
        s.cancelled = true;
        this.message =
          "Textify could not start the microphone. Check permission and the selected device.";
      } finally {
        if (s.cancelled) {
          if (s.ready) await this.ports.stop(s.id, true).catch(() => {});
          this.clear(s);
          this.update(this.message ? "error" : "idle", this.message);
        }
      }
    })();
  }
  private samples(s: Session, data: Float32Array) {
    if (
      s.cancelled ||
      this.session !== s ||
      !["armed", "recording", "processing"].includes(this.phase)
    )
      return;
    if (data.some((x) => !Number.isFinite(x) || Math.abs(x) > 1)) {
      void this.cancel("Microphone returned an unsupported audio format.");
      return;
    }
    const frame = data.slice(0, MAX_SAMPLES - s.count);
    if (!frame.length) return;
    s.frames.push(frame);
    s.count += frame.length;
    s.guard.accept(frame);
    this.level = Math.min(1, rms(frame) * 8);
    this.ports.changed();
    if (s.count >= MAX_SAMPLES) void this.finish(s);
  }
  async release() {
    const s = this.session;
    if (!s || !["armed", "recording"].includes(this.phase)) return;
    if (!s.ready || this.now() - s.started < 250) await this.cancel();
    else await this.finish(s);
  }
  otherKey(modifier = false) {
    if (
      this.phase === "armed" ||
      (this.phase === "recording" && !modifier && !this.session?.guard.detected)
    )
      void this.cancel();
  }
  async cancel(message = "") {
    const s = this.session;
    if (!s) {
      this.pending = "";
      this.update("idle");
      return;
    }
    s.cancelled = true;
    this.timers();
    this.message = message;
    // Remain busy until an in-flight microphone start has been drained.
    await s.startTask;
    if (this.processingTask) await this.processingTask;
    else if (s.ready) await this.ports.stop(s.id, true).catch(() => {});
    this.clear(s);
    this.update(message ? "error" : "idle", message);
  }
  private clear(s: Session) {
    for (const frame of s.frames) frame.fill(0);
    s.frames = [];
    s.count = 0;
    if (this.session === s) {
      this.session = undefined;
      this.level = 0;
      this.timers();
    }
  }
  private finish(s: Session) {
    if (
      s.cancelled ||
      this.session !== s ||
      !["armed", "recording"].includes(this.phase)
    )
      return Promise.resolve();
    const task = this.process(s);
    this.processingTask = task;
    void task.finally(() => {
      if (this.processingTask === task) this.processingTask = undefined;
    });
    return task;
  }
  private async process(s: Session) {
    if (
      s.cancelled ||
      this.session !== s ||
      !["armed", "recording"].includes(this.phase)
    )
      return;
    this.timers();
    this.update("processing", "Transcribing on this device…");
    let pcm: Float32Array = new Float32Array();
    try {
      await this.ports.stop(s.id, false);
      if (s.cancelled) return;
      if (!s.count) {
        this.update(
          "error",
          "No microphone audio was received. Check the selected input and reopen Textify.",
        );
        return;
      }
      const all = new Float32Array(s.count);
      let offset = 0;
      for (const frame of s.frames) {
        all.set(frame, offset);
        offset += frame.length;
        frame.fill(0);
      }
      s.frames = [];
      pcm = trimSilence(all);
      all.fill(0);
      if (!pcm.length) {
        this.update(
          "error",
          "No speech detected. Check the selected microphone and its input level, then try again.",
        );
        return;
      }
      let text = "";
      for (const audio of windows(pcm)) {
        const chunk = await this.ports.transcribe(audio);
        if (s.cancelled) return;
        if (chunk === null) {
          this.update(
            "error",
            "Textify could not recognize clear speech. Check the microphone and dictation language, then try again.",
          );
          return;
        }
        text = stitch(text, chunk);
      }
      text = processText(text, this.replacements(), this.language());
      if (!text.trim() || s.cancelled) {
        if (!s.cancelled)
          this.update(
            "error",
            "Textify could not recognize clear speech. Check the microphone and dictation language, then try again.",
          );
        return;
      }
      if (!s.target) {
        this.pending = text;
        this.update(
          "copy",
          "Your dictation is ready. Copy it, then paste into your app.",
        );
        return;
      }
      this.update("inserting");
      const result = await this.ports.insert(text, s.target);
      if (s.cancelled) return;
      if (result === "unavailable") {
        this.pending = text;
        this.update(
          "copy",
          "Automatic insertion is unavailable here. Copy your dictation to paste it.",
        );
      } else if (result === "skipped") {
        this.update(
          "error",
          "Textify could not confirm delivery to the original app. Check that text field before dictating again.",
        );
      } else this.update("idle");
    } catch (error) {
      if (!s.cancelled)
        this.update(
          "error",
          engineError(error) ??
            "Dictation could not finish. Check the model and microphone, then try again.",
        );
    } finally {
      pcm.fill(0);
      this.clear(s);
      this.ports.changed();
    }
  }
  async copy(write: (text: string) => Promise<void>) {
    if (this.busy || !this.pending) return;
    this.copying = true;
    try {
      await write(this.pending);
      this.pending = "";
      this.update("idle");
    } finally {
      this.copying = false;
      this.ports.changed();
    }
  }
  dismiss() {
    if (this.copying) return;
    this.pending = "";
    if (!this.busy) this.update("idle");
  }
}
