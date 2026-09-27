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
  it("reports nothing before the folder exists", async () => {
    expect(await new RecordingStore(await fixture()).summary()).toEqual({ count: 0, seconds: 0 });
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

  it("totals saved records and skips records broken during review", async () => {
    const directory = await fixture();
    const store = new RecordingStore(directory);
    void store.save(sample(3), new Date("2026-09-27T10:00:00.000Z"));
    void store.save(sample(1), new Date("2026-09-27T10:00:01.000Z"));
    expect(await store.summary()).toEqual({ count: 2, seconds: 4 });
    await writeFile(join(directory, "broken.json"), "{");
    expect(await store.summary()).toEqual({ count: 2, seconds: 4 });
  });
});
