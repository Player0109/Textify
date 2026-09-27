import { mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { SAMPLE_RATE } from "../core/audio";
import type { RecordingsSummary } from "../shared";

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
    const task = this.pending.catch(() => {}).then(async () => {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      await writeFile(join(this.directory, `${id}.wav`), audio, { mode: 0o600 });
      // The record appears only after its audio is complete.
      const record = join(this.directory, `${id}.json`);
      await writeFile(`${record}.tmp`, metadata, { mode: 0o600 });
      await rename(`${record}.tmp`, record);
    });
    this.pending = task;
    return task;
  }

  flush(): Promise<void> {
    return this.pending;
  }

  async summary(): Promise<RecordingsSummary> {
    await this.pending.catch(() => {});
    let names: string[];
    try {
      names = await readdir(this.directory);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT")
        return { count: 0, seconds: 0 };
      throw error;
    }
    const summary = { count: 0, seconds: 0 };
    for (const name of names.filter((name) => name.endsWith(".json"))) {
      try {
        const { seconds } = JSON.parse(
          await readFile(join(this.directory, name), "utf8"),
        );
        if (!Number.isFinite(seconds) || seconds <= 0) continue;
        summary.count++;
        summary.seconds += seconds;
      } catch {
        /* Skip records edited into invalid JSON during review. */
      }
    }
    return summary;
  }
}
