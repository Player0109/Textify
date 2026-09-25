import { createHash } from "node:crypto";
import {
  mkdtemp,
  readFile,
  rm,
  writeFile,
  mkdir,
  readdir,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Models } from "../src/main/models";
const directories: string[] = [];
afterEach(async () => {
  vi.unstubAllGlobals();
  await Promise.all(
    directories
      .splice(0)
      .map((dir) => rm(dir, { recursive: true, force: true })),
  );
});
async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "textify-storage-"));
  directories.push(directory);
  const bytes = Buffer.from("catalog-authorized-fixture");
  const model = new Models("", directory, () => {});
  const file = {
    filename: "fixture.bin",
    url: "https://example.invalid/fixture",
    sha256: createHash("sha256").update(bytes).digest("hex"),
    sizeBytes: bytes.length,
  };
  model.entries = [
    {
      id: model.id,
      name: "Test",
      engine: "whisper_cpp",
      checkpointID: "test",
      description: "Test",
      variant: "GGML",
      provider: "Test",
      license: "MIT",
      source: "https://example.invalid",
      vocabulary: true,
      file,
      files: [file],
      directory: false,
      bytes: file.sizeBytes,
      installed: false,
      status: "not-installed",
      languages: ["en"],
      resumable: false,
      storedBytes: 0,
      restorations: [],
    },
  ];
  return { directory, model, bytes };
}
describe("verified model storage", () => {
  async function directoryFixture() {
    const h = await fixture();
    const entry = h.model.entries[0];
    entry.engine = "audio_cpp";
    entry.directory = true;
    entry.file.filename = "model.safetensors";
    entry.files.push({ ...entry.file, filename: "config.json" });
    entry.bytes *= 2;
    const source = join(h.directory, "original");
    await mkdir(source);
    for (const f of entry.files)
      await writeFile(join(source, f.filename), h.bytes);
    return { ...h, source, entry };
  }
  it("imports and verifies every approved directory file, ignoring extra source contents", async () => {
    const h = await directoryFixture();
    await writeFile(join(h.source, "untrusted.gguf"), "extra");
    await h.model.install(h.source);
    expect(h.model.installed).toBe(true);
    expect(await readdir(h.model.path)).toEqual([
      "config.json",
      "model.safetensors",
    ]);
    expect(h.entry.storedBytes).toBe(h.bytes.length * 2);
    await writeFile(join(h.model.path, "untrusted.gguf"), "extra");
    await expect(h.model.verify()).rejects.toThrow("model_integrity");
    await h.model.remove(h.model.id);
    expect(h.entry.storedBytes).toBe(0);
    expect(await readFile(join(h.source, "model.safetensors"))).toEqual(
      h.bytes,
    );
  });
  it("preserves an installed directory when a replacement has one corrupt file", async () => {
    const h = await directoryFixture();
    await h.model.install(h.source);
    await writeFile(join(h.source, "config.json"), "bad");
    await expect(h.model.install(h.source)).rejects.toThrow("model_integrity");
    expect(h.model.installed).toBe(true);
    expect(await readFile(join(h.model.path, "config.json"))).toEqual(h.bytes);
  });
  it("resumes a directory after interruption without redownloading completed verified files", async () => {
    const h = await directoryFixture();
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(new Response(h.bytes))
      .mockRejectedValueOnce(new Error("offline"));
    vi.stubGlobal("fetch", fetcher);
    await expect(h.model.install()).rejects.toThrow("offline");
    expect(h.entry.installed).toBe(false);
    expect(h.entry.resumable).toBe(true);
    fetcher.mockResolvedValueOnce(new Response(h.bytes));
    await h.model.install();
    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(h.model.installed).toBe(true);
  });
  it("retains the GGUF extension required by the audio.cpp loader", async () => {
    const h = await fixture();
    h.model.entries[0].engine = "audio_cpp";
    h.model.entries[0].file.filename = "fixture.gguf";
    const source = join(h.directory, "source.gguf");
    await writeFile(source, h.bytes);
    await h.model.install(source);
    expect(h.model.path).toBe(join(h.directory, `${h.model.id}.gguf`));
    expect(h.model.installed).toBe(true);
    expect(h.model.entries[0].storedBytes).toBe(h.bytes.length);
    await h.model.remove(h.model.id);
    expect(h.model.entries[0].storedBytes).toBe(0);
    expect(await readFile(source)).toEqual(h.bytes);
  });
  it("imports only matching bytes and preserves the source", async () => {
    const h = await fixture(),
      source = join(h.directory, "source.bin");
    await writeFile(source, h.bytes);
    await h.model.install(source);
    expect(h.model.installed).toBe(true);
    expect(await readFile(h.model.path)).toEqual(h.bytes);
    expect(await readFile(source)).toEqual(h.bytes);
  });
  it("rejects corrupt imports without replacing an installed model", async () => {
    const h = await fixture(),
      source = join(h.directory, "source.bin");
    await writeFile(h.model.path, h.bytes);
    await writeFile(source, "wrong model");
    await expect(h.model.install(source)).rejects.toThrow("model_integrity");
    expect(await readFile(h.model.path)).toEqual(h.bytes);
    expect(h.model.busy).toBe(false);
    await expect(readFile(`${h.model.path}.partial`)).rejects.toThrow();
  });
  it("rejects oversized downloads without accepting a partial artifact", async () => {
    const h = await fixture();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(Buffer.concat([h.bytes, h.bytes]))),
    );
    await expect(h.model.install()).rejects.toThrow("download_size");
    expect(h.model.installed).toBe(false);
    await expect(readFile(h.model.path)).rejects.toThrow();
  });
  it("checks the checksum after streaming a complete download", async () => {
    const h = await fixture();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(h.bytes)),
    );
    await h.model.install();
    expect(await readFile(h.model.path)).toEqual(h.bytes);
  });
});
