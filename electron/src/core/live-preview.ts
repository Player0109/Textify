export interface StreamingPorts {
  beginStream(): Promise<void>;
  pushStream(samples: Float32Array): Promise<string>;
  finishStream(): Promise<string>;
  resetStream(): Promise<void>;
}
const CHUNK = 5120; // 320 ms at 16 kHz, matching the Confucius decoder.
const WINDOW = 400000; // Keep the decoder and queued preview audio within 25 s.

/** Ephemeral preview only. Final recognition always uses the complete capture. */
export class LivePreview {
  private queue = new Float32Array(0);
  private task?: Promise<void>;
  private closing?: Promise<void>;
  private stopped = false;
  private open = false;
  private restart = false;
  private count = 0;
  private prefix = "";
  private text = "";
  private error?: unknown;
  constructor(
    private ports: StreamingPorts,
    private changed: (text: string) => void,
  ) {}
  push(samples: Float32Array) {
    if (this.stopped || this.error) return;
    const length = Math.min(WINDOW, this.queue.length + samples.length);
    const next = new Float32Array(length);
    if (this.queue.length + samples.length > WINDOW) {
      // If inference falls behind, abandon the stale preview window. The
      // independent final capture still contains every sample.
      this.restart = true;
    }
    const recent = samples.subarray(Math.max(0, samples.length - length));
    const keep = length - recent.length;
    next.set(this.queue.subarray(this.queue.length - keep));
    next.set(recent, keep);
    this.queue.fill(0);
    this.queue = next;
    if (!this.task && this.queue.length >= CHUNK) this.task = this.drain();
  }
  private async drain() {
    try {
      while (!this.stopped && this.queue.length >= CHUNK) {
        if (this.restart) {
          if (this.open) await this.ports.resetStream();
          this.open = false;
          this.count = 0;
          this.prefix = this.text = "";
          this.restart = false;
        }
        if (!this.open) {
          await this.ports.beginStream();
          this.open = true;
        }
        if (this.stopped) break;
        const size = Math.min(CHUNK, WINDOW - this.count);
        const chunk = this.queue.slice(0, size);
        const remaining = this.queue.slice(size);
        this.queue.fill(0);
        this.queue = remaining;
        let text: string;
        try {
          text = await this.ports.pushStream(chunk);
        } finally {
          chunk.fill(0);
        }
        this.count += size;
        if (!this.stopped && !this.restart && text) {
          // audio.cpp events contain token deltas, including leading whitespace.
          this.text = (this.text + text).slice(-2000);
          this.changed((this.prefix + this.text).slice(-2000));
        }
        if (this.count === WINDOW && !this.stopped) {
          const final = await this.ports.finishStream();
          await this.ports.resetStream();
          this.open = false;
          this.count = 0;
          this.prefix = (this.prefix + final + (final ? " " : "")).slice(-2000);
          this.text = "";
        }
      }
    } catch (error) {
      this.error = error;
      this.queue.fill(0);
      this.queue = new Float32Array(0);
    } finally {
      this.task = undefined;
    }
  }
  stop(): Promise<void> {
    return (this.closing ??= this.close());
  }
  private async close() {
    this.stopped = true;
    this.queue.fill(0);
    this.queue = new Float32Array(0);
    await this.task;
    try {
      if (this.open) await this.ports.resetStream();
    } finally {
      this.open = false;
      this.prefix = this.text = "";
    }
    if (this.error) throw this.error;
  }
}
