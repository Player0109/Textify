import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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
      file,
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
