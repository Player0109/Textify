import { stitch, windows } from "../core/audio";
import type { ModelView } from "../shared";
import type { RecordingStore } from "./recordings";
import { WhisperWorker } from "./worker";

const families: [string, RegExp][] = [
  ["whisper", /^(ggml|whisper)-/],
  ["parakeet", /^parakeet-/],
  ["qwen3-asr", /^qwen3-asr-/],
];
const family = (id: string) =>
  families.find(([, pattern]) => pattern.test(id))?.[0];

// The largest installed model of each family other than the clip's own that
// supports the clip's language. Different families make fewer shared mistakes.
export function committee(
  models: ModelView[],
  modelID: string,
  language: string,
): ModelView[] {
  const chosen = new Map<string, ModelView>();
  for (const model of models) {
    const name = family(model.id);
    if (
      !name ||
      name === family(modelID) ||
      model.status !== "installed" ||
      !model.languages.includes(language)
    )
      continue;
    if ((chosen.get(name)?.bytes ?? -1) < model.bytes) chosen.set(name, model);
  }
  return [...chosen.values()];
}

// Transcribes saved clips with the committee models, one clip at a time while
// dictation is idle, and stores each model's text in the clip's record.
export class Comparison {
  private workers = new Map<string, WhisperWorker>();
  private failed = new Set<string>();
  private running = false;
  private again = false;
  private release?: ReturnType<typeof setTimeout>;

  constructor(
    private binary: string,
    private store: RecordingStore,
    private models: () => ModelView[],
    private pathFor: (id: string) => string,
    private enabled: () => boolean,
    private idle: () => boolean,
    private compared: () => void,
  ) {}

  schedule() {
    if (this.running) {
      this.again = true;
      return;
    }
    this.running = true;
    clearTimeout(this.release);
    void this.run()
      .catch(() => {})
      .finally(() => {
        this.running = false;
        if (this.again) {
          this.again = false;
          this.schedule();
        } else this.release = setTimeout(() => this.stop(), 120_000);
      });
  }

  private async run() {
    for (const clip of await this.store.list()) {
      for (const model of committee(this.models(), clip.modelID, clip.language)) {
        const key = `${clip.id} ${model.id}`;
        if (
          model.id in clip.comparisons ||
          this.failed.has(model.id) ||
          this.failed.has(key)
        )
          continue;
        while (this.enabled() && !this.idle())
          await new Promise((resolve) => setTimeout(resolve, 2000));
        if (!this.enabled()) return;
        const worker = await this.worker(model, clip.language);
        if (!worker) continue;
        let samples: Float32Array | undefined;
        try {
          samples = await this.store.samples(clip.id);
          let text = "";
          for (const audio of windows(samples))
            text = stitch(text, (await worker.transcribe(audio)) ?? "");
          await this.store.compare(clip.id, model.id, text);
          this.compared();
        } catch {
          this.failed.add(key);
        } finally {
          samples?.fill(0);
        }
      }
    }
  }

  private async worker(model: ModelView, language: string) {
    const key = `${model.id} ${language}`;
    const existing = this.workers.get(key);
    if (existing?.ready) return existing;
    const worker = existing ?? new WhisperWorker(this.binary, () => {});
    this.workers.set(key, worker);
    try {
      await worker.load(this.pathFor(model.id), language, [], model.engine);
      return worker;
    } catch {
      this.failed.add(model.id);
      this.workers.delete(key);
      worker.stop();
      return undefined;
    }
  }

  // Resolves when every comparison worker has exited.
  async stop() {
    clearTimeout(this.release);
    const exits = [...this.workers.values()].map((worker) => worker.stop());
    this.workers.clear();
    await Promise.all(exits);
  }
}
