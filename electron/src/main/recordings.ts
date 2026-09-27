import { mkdir, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { SAMPLE_RATE } from "../core/audio";
import type { RecordingEntry } from "../shared";

export type Recording = {
  audio: Float32Array;
  modelText: string;
  finalText: string;
  modelID: string;
  language: string;
};

// 16-bit mono PCM at the model's input rate.
export function wav(samples: Float32Array): Buffer {
  const bytes = samples.length * 2;
  const out = Buffer.alloc(44 + bytes);
  out.write("RIFF", 0, "ascii");
  out.writeUInt32LE(36 + bytes, 4);
  out.write("WAVEfmt ", 8, "ascii");
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SAMPLE_RATE, 24);
  out.writeUInt32LE(SAMPLE_RATE * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write("data", 36, "ascii");
  out.writeUInt32LE(bytes, 40);
  for (let i = 0; i < samples.length; i++)
    out.writeInt16LE(
      Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767),
      44 + i * 2,
    );
  return out;
}

// Record names are save timestamps, e.g. 2026-09-27T10-15-30-123Z.
const ID = /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/;

export class RecordingStore {
  private pending: Promise<void> = Promise.resolve();

  constructor(readonly directory: string) {}

  save(recording: Recording, date = new Date()): Promise<void> {
    // Encode before any await: the caller clears the audio buffer on return.
    const id = date.toISOString().replace(/[:.]/g, "-");
    const audio = wav(recording.audio);
    const metadata = JSON.stringify(
      {
        version: 1,
        audio: `${id}.wav`,
        createdAt: date.toISOString(),
        modelID: recording.modelID,
        language: recording.language,
        seconds: recording.audio.length / SAMPLE_RATE,
        modelText: recording.modelText,
        finalText: recording.finalText,
        correctedText: null,
      },
      null,
      2,
    );
    return this.queue(async () => {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      await writeFile(join(this.directory, `${id}.wav`), audio, { mode: 0o600 });
      // The record appears only after its audio is complete.
      await this.write(this.file(id, "json"), metadata);
    });
  }

  flush(): Promise<void> {
    return this.pending;
  }

  async list(): Promise<RecordingEntry[]> {
    await this.pending.catch(() => {});
    let names: string[];
    try {
      names = await readdir(this.directory);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw error;
    }
    const entries: RecordingEntry[] = [];
    for (const name of names) {
      const id = name.slice(0, -".json".length);
      if (!name.endsWith(".json") || !ID.test(id)) continue;
      try {
        const { createdAt, seconds, modelID, modelText, finalText, correctedText } =
          JSON.parse(await readFile(join(this.directory, name), "utf8"));
        if (
          !Number.isFinite(seconds) ||
          seconds <= 0 ||
          ![createdAt, modelID, modelText, finalText].every(
            (value) => typeof value === "string",
          )
        )
          continue;
        entries.push({
          id,
          createdAt,
          seconds,
          modelID,
          modelText,
          finalText,
          correctedText: typeof correctedText === "string" ? correctedText : null,
        });
      } catch {
        /* Skip records edited into invalid JSON during review. */
      }
    }
    // Timestamp names sort chronologically; newest first.
    return entries.sort((a, b) => b.id.localeCompare(a.id));
  }

  async audio(id: string): Promise<Buffer> {
    return readFile(this.file(id, "wav"));
  }

  async correct(id: string, text: string): Promise<void> {
    const record = this.file(id, "json");
    if (typeof text !== "string" || !text.trim() || text.length > 20_000)
      throw new Error("recording_text");
    return this.queue(async () => {
      const data = JSON.parse(await readFile(record, "utf8"));
      data.correctedText = text.trim();
      await this.write(record, JSON.stringify(data, null, 2));
    });
  }

  async remove(id: string): Promise<void> {
    const record = this.file(id, "json");
    const audio = this.file(id, "wav");
    return this.queue(async () => {
      await rm(record, { force: true });
      await rm(audio, { force: true });
    });
  }

  private file(id: string, extension: "json" | "wav") {
    if (typeof id !== "string" || !ID.test(id)) throw new Error("recording_id");
    return join(this.directory, `${id}.${extension}`);
  }

  private async write(path: string, contents: string) {
    await writeFile(`${path}.tmp`, contents, { mode: 0o600 });
    await rename(`${path}.tmp`, path);
  }

  private queue(work: () => Promise<void>): Promise<void> {
    const task = this.pending.catch(() => {}).then(work);
    this.pending = task;
    return task;
  }
}
