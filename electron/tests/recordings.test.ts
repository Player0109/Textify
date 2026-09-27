import { mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { RecordingStore } from "../src/main/recordings";

const directories: string[] = [];
afterEach(async () => {
  await Promise.all(directories.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "textify-recordings-"));
  directories.push(directory);
  return join(directory, "Recordings");
}

const sample = (seconds: number) => ({
  audio: new Float32Array(seconds * 16000).fill(0.5),
  modelText: "hello comma world",
  finalText: "Hello, world",
  modelID: "qwen3-asr-1.7b-bf16",
  language: "en",
});

describe("training recordings", () => {
  it("lists nothing before the folder exists", async () => {
    expect(await new RecordingStore(await fixture()).list()).toEqual([]);
  });

  it("writes 16 kHz mono WAV audio with a reviewable private record", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    const input = sample(2);
    const saving = store.save(input, new Date("2026-09-27T10:15:30.123Z"));
    input.audio.fill(0);
    await saving;

    const audio = await readFile(join(directory, "2026-09-27T10-15-30-123Z.wav"));
    expect(audio.toString("ascii", 0, 4)).toBe("RIFF");
    expect(audio.toString("ascii", 8, 16)).toBe("WAVEfmt ");
    expect(audio.readUInt16LE(20)).toBe(1);
    expect(audio.readUInt16LE(22)).toBe(1);
    expect(audio.readUInt32LE(24)).toBe(16000);
    expect(audio.readUInt16LE(34)).toBe(16);
    expect(audio.readUInt32LE(40)).toBe(64000);
    expect(audio.length).toBe(44 + 64000);
    expect(audio.readInt16LE(44)).toBe(16384);

    const record = JSON.parse(await readFile(join(directory, "2026-09-27T10-15-30-123Z.json"), "utf8"));
    expect(record).toEqual({
      version: 1,
      audio: "2026-09-27T10-15-30-123Z.wav",
      createdAt: "2026-09-27T10:15:30.123Z",
      modelID: "qwen3-asr-1.7b-bf16",
      language: "en",
      seconds: 2,
      modelText: "hello comma world",
      finalText: "Hello, world",
      correctedText: null,
    });
    if (process.platform !== "win32") {
      expect((await stat(directory)).mode & 0o777).toBe(0o700);
      expect((await stat(join(directory, record.audio))).mode & 0o777).toBe(0o600);
    }
    expect(await readdir(directory)).not.toContain("2026-09-27T10-15-30-123Z.json.tmp");
  });

  it("lists records newest first and skips records broken during review", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    void store.save(sample(3), new Date("2026-09-27T10:00:00.000Z"));
    void store.save(sample(1), new Date("2026-09-27T10:00:01.000Z"));
    const listed = await store.list();
    expect(listed.map((entry) => [entry.id, entry.seconds])).toEqual([
      ["2026-09-27T10-00-01-000Z", 1],
      ["2026-09-27T10-00-00-000Z", 3],
    ]);
    expect(listed[0]).toMatchObject({
      createdAt: "2026-09-27T10:00:01.000Z",
      modelID: "qwen3-asr-1.7b-bf16",
      modelText: "hello comma world",
      finalText: "Hello, world",
      correctedText: null,
      language: "en",
      comparisons: {},
    });
    await writeFile(join(directory, "2026-09-27T10-00-02-000Z.json"), "{");
    await writeFile(join(directory, "notes.json"), "{}");
    expect(await store.list()).toHaveLength(2);
  });

  it("saves a trimmed correction and returns the clip's audio", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    const id = "2026-09-27T10-00-00-000Z";
    void store.save(sample(1), new Date("2026-09-27T10:00:00.000Z"));
    await store.correct(id, "  hello comma word \n");
    const record = JSON.parse(await readFile(join(directory, `${id}.json`), "utf8"));
    expect(record.correctedText).toBe("hello comma word");
    expect(record.modelText).toBe("hello comma world");
    expect((await store.list())[0].correctedText).toBe("hello comma word");
    expect((await store.audio(id)).length).toBe(44 + 32000);
    await expect(store.correct(id, "   ")).rejects.toThrow("recording_text");
    expect(await readdir(directory)).not.toContain(`${id}.json.tmp`);
  });

  it("keeps other models' text beside the correction and reads the audio back", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    const id = "2026-09-27T10-00-00-000Z";
    void store.save(sample(1), new Date("2026-09-27T10:00:00.000Z"));
    void store.compare(id, "whisper-large-v3-q5_0", "hello comma world");
    void store.correct(id, "hello comma word");
    await store.compare(id, "parakeet-tdt-0.6b-v3-f16", "Hello, comma word.");
    const [entry] = await store.list();
    expect(entry.comparisons).toEqual({
      "whisper-large-v3-q5_0": "hello comma world",
      "parakeet-tdt-0.6b-v3-f16": "Hello, comma word.",
    });
    expect(entry.correctedText).toBe("hello comma word");
    const samples = await store.samples(id);
    expect(samples.length).toBe(16000);
    expect(samples[0]).toBeCloseTo(0.5, 3);
    await writeFile(
      join(directory, `${id}.json`),
      JSON.stringify({ ...JSON.parse(await readFile(join(directory, `${id}.json`), "utf8")), comparisons: "text" }),
    );
    expect((await store.list())[0].comparisons).toEqual({});
  });

  it("deletes a clip's record and audio", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    void store.save(sample(1), new Date("2026-09-27T10:00:00.000Z"));
    void store.save(sample(1), new Date("2026-09-27T10:00:01.000Z"));
    await store.remove("2026-09-27T10-00-00-000Z");
    expect((await readdir(directory)).sort()).toEqual([
      "2026-09-27T10-00-01-000Z.json",
      "2026-09-27T10-00-01-000Z.wav",
    ]);
  });

  it("refuses names outside the recording folder", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    await writeFile(join(directory, "..", "secret.wav"), "private");
    for (const id of ["../secret", "2026-09-27T10-00-00-000Z/../../secret", "", "notes"]) {
      await expect(store.audio(id)).rejects.toThrow("recording_id");
      await expect(store.correct(id, "text")).rejects.toThrow("recording_id");
      await expect(store.remove(id)).rejects.toThrow("recording_id");
    }
    expect(await readFile(join(directory, "..", "secret.wav"), "utf8")).toBe("private");
  });
});
