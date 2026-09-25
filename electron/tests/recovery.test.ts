import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it, vi } from "vitest";
import { transfer, type ModelFile } from "../src/main/transfer";
const directories: string[] = [];
afterEach(async () => {
  vi.unstubAllGlobals();
  await Promise.all(
    directories
      .splice(0)
      .map((path) => rm(path, { recursive: true, force: true })),
  );
});
async function fixture() {
  const path = join(
    await mkdtemp(join(tmpdir(), "textify-resume-")),
    "model.bin",
  );
  directories.push(join(path, ".."));
  const bytes = Buffer.from("a verified model with enough bytes to split"),
    prefix = bytes.subarray(0, 12);
  const file: ModelFile = {
    filename: "model.bin",
    url: "https://example.invalid/model",
    sha256: createHash("sha256").update(bytes).digest("hex"),
    sizeBytes: bytes.length,
  };
  await writeFile(`${path}.partial`, prefix);
  await writeFile(
    `${path}.partial.json`,
    JSON.stringify({
      ...file,
      received: prefix.length,
      prefixSHA256: createHash("sha256").update(prefix).digest("hex"),
      etag: '"unchanged"',
    }),
  );
  return { path, file, bytes, prefix };
}
describe("model download recovery", () => {
  it("resumes the verified prefix with Range and verifies the final checksum", async () => {
    const h = await fixture();
    const fetcher = vi.fn(
      async (_url: unknown, _options: unknown) =>
        new Response(h.bytes.subarray(h.prefix.length), {
          status: 206,
          headers: {
            "content-range": `bytes ${h.prefix.length}-${h.bytes.length - 1}/${h.bytes.length}`,
          },
        }),
    );
    vi.stubGlobal("fetch", fetcher);
    const result = await transfer(
      h.file,
      h.path,
      new AbortController().signal,
      () => {},
    );
    expect(fetcher.mock.calls[0]?.[1]).toMatchObject({
      headers: { Range: "bytes=12-", "If-Range": '"unchanged"' },
    });
    expect(await readFile(result)).toEqual(h.bytes);
  });
  it("restarts when the server ignores Range instead of appending duplicate bytes", async () => {
    const h = await fixture();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(h.bytes)),
    );
    expect(
      await readFile(
        await transfer(h.file, h.path, new AbortController().signal, () => {}),
      ),
    ).toEqual(h.bytes);
  });
  it("discards a modified prefix before a fresh download", async () => {
    const h = await fixture();
    await writeFile(`${h.path}.partial`, Buffer.alloc(12));
    const fetcher = vi.fn(
      async (_url: unknown, _options: unknown) => new Response(h.bytes),
    );
    vi.stubGlobal("fetch", fetcher);
    await transfer(h.file, h.path, new AbortController().signal, () => {});
    expect(fetcher.mock.calls[0]?.[1]).toMatchObject({ headers: {} });
  });
  it("refuses an incorrect Content-Range without consuming it", async () => {
    const h = await fixture();
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(h.bytes, {
            status: 206,
            headers: {
              "content-range": `bytes 0-${h.bytes.length - 1}/${h.bytes.length}`,
            },
          }),
      ),
    );
    await expect(
      transfer(h.file, h.path, new AbortController().signal, () => {}),
    ).rejects.toThrow("download_range");
    expect(await readFile(`${h.path}.partial`)).toEqual(h.prefix);
  });
  it("checkpoints an interrupted stream and resumes after relaunch", async () => {
    const h = await fixture();
    await rm(`${h.path}.partial.json`);
    let sent = false;
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            new ReadableStream({
              pull(controller) {
                if (!sent) {
                  sent = true;
                  controller.enqueue(h.prefix);
                } else controller.error(new Error("connection_lost"));
              },
            }),
          ),
      ),
    );
    await expect(
      transfer(h.file, h.path, new AbortController().signal, () => {}),
    ).rejects.toThrow("connection_lost");
    expect(
      JSON.parse(await readFile(`${h.path}.partial.json`, "utf8")).received,
    ).toBe(12);
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(h.bytes.subarray(12), {
            status: 206,
            headers: {
              "content-range": `bytes 12-${h.bytes.length - 1}/${h.bytes.length}`,
            },
          }),
      ),
    );
    expect(
      await readFile(
        await transfer(h.file, h.path, new AbortController().signal, () => {}),
      ),
    ).toEqual(h.bytes);
  });
});
