import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const { feedName, refreshWindowsFeed, verifyUpdateFeed, verifyWindowsUpdate } =
  await import(pathToFileURL(resolve("scripts/update-feeds.mjs")).href);
const version = "0.2.0-preview.24";
const appImage = `Textify-${version}-linux-x86_64.AppImage`;
const deb = `Textify-${version}-linux-amd64.deb`;
const exe = `Textify-${version}-win-x64.exe`;
let directory: string;

const sha512 = (bytes: Buffer) => createHash("sha512").update(bytes).digest("base64");

// electron-builder's layout: one entry per installer, then the first one again
// at the top level for old updaters.
function feed(files: { url: string; bytes: Buffer }[], overrides: Record<string, string> = {}) {
  const lines = [`version: ${overrides.version ?? version}`, "files:"];
  for (const { url, bytes } of files)
    lines.push(`  - url: ${url}`, `    sha512: ${overrides[url] ?? sha512(bytes)}`, `    size: ${bytes.length}`);
  lines.push(`path: ${files[0].url}`, `sha512: ${sha512(files[0].bytes)}`,
    "releaseDate: '2026-10-01T00:00:00.000Z'", "");
  return lines.join("\n");
}

// A minimal PE32 file whose security directory points at a certificate table.
function windowsExecutable(signer?: string) {
  const bytes = Buffer.alloc(0x200);
  bytes.writeUInt32LE(0x80, 0x3c);
  bytes.write("PE\0\0", 0x80, "latin1");
  bytes.writeUInt16LE(0x10b, 0x98);
  if (!signer) return bytes;
  const table = Buffer.from(`certificate for ${signer}`);
  bytes.writeUInt32LE(bytes.length, 0x98 + 96 + 32);
  bytes.writeUInt32LE(table.length, 0x98 + 96 + 36);
  return Buffer.concat([bytes, table]);
}

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "textify-feeds-test-"));
});

afterEach(async () => {
  await rm(directory, { recursive: true });
});

describe("update feed names", () => {
  it("matches electron-builder's channel names on each platform", () => {
    expect(feedName(version, "mac")).toBe("preview-mac.yml");
    expect(feedName(version, "windows")).toBe("preview.yml");
    expect(feedName(version, "linux")).toBe("preview-linux.yml");
    expect(feedName("1.0.0", "windows")).toBe("latest.yml");
  });
});

describe("Linux update feed", () => {
  const files = [
    { url: deb, bytes: Buffer.from("debian package") },
    { url: appImage, bytes: Buffer.from("appimage") },
  ];

  beforeEach(async () => {
    for (const { url, bytes } of files) await writeFile(join(directory, url), bytes);
  });

  it("accepts a feed that lists both packages in either order", async () => {
    await writeFile(join(directory, "preview-linux.yml"), feed(files));
    await verifyUpdateFeed(directory, version, "linux", [appImage, deb]);
    await writeFile(join(directory, "preview-linux.yml"), feed([...files].reverse()));
    await verifyUpdateFeed(directory, version, "linux", [appImage, deb]);
  });

  it.each([
    [{ version: "0.2.0-preview.23" }, files, "package version"],
    [{ [deb]: "stale" }, files, `does not match ${deb}`],
    [{}, files.slice(1), "must list only"],
  ])("rejects a feed that does not match the release: %o", async (overrides, listed, message) => {
    await writeFile(join(directory, "preview-linux.yml"), feed(listed, overrides));
    await expect(verifyUpdateFeed(directory, version, "linux", [appImage, deb])).rejects.toThrow(message);
  });

  it("requires the feed", async () => {
    await expect(verifyUpdateFeed(directory, version, "linux", [appImage, deb]))
      .rejects.toThrow("Missing update feed: preview-linux.yml");
  });
});

describe("Windows update feed", () => {
  it("leaves an unsigned installer out of the update feed", async () => {
    const bytes = windowsExecutable();
    await writeFile(join(directory, exe), bytes);
    await expect(verifyWindowsUpdate(directory, version)).resolves.toBe(false);
    await writeFile(join(directory, "preview.yml"), feed([{ url: exe, bytes }]));
    await expect(verifyWindowsUpdate(directory, version)).rejects.toThrow("Remove preview.yml");
  });

  it("rejects another publisher's signature", async () => {
    const bytes = windowsExecutable("Someone Else");
    await writeFile(join(directory, exe), bytes);
    await writeFile(join(directory, "preview.yml"), feed([{ url: exe, bytes }]));
    await expect(verifyWindowsUpdate(directory, version)).rejects.toThrow("must be signed by SignPath Foundation");
    await expect(refreshWindowsFeed(directory, version)).rejects.toThrow("must be signed by SignPath Foundation");
  });

  it("rebuilds the blockmap and feed entry from the signed installer", async () => {
    const unsigned = windowsExecutable();
    await writeFile(join(directory, "preview.yml"), feed([{ url: exe, bytes: unsigned }]));
    await writeFile(join(directory, exe), windowsExecutable("SignPath Foundation"));
    await expect(verifyWindowsUpdate(directory, version)).rejects.toThrow(`does not match ${exe}`);

    await refreshWindowsFeed(directory, version);
    const signed = await readFile(join(directory, exe));
    const text = await readFile(join(directory, "preview.yml"), "utf8");
    expect(text).not.toContain(sha512(unsigned));
    expect(text.match(new RegExp(sha512(signed).replace(/[+/]/g, "\\$&"), "g"))).toHaveLength(2);
    expect(text).toContain(`    size: ${signed.length}\n`);
    expect((await stat(join(directory, `${exe}.blockmap`))).size).toBeGreaterThan(0);
    await expect(verifyWindowsUpdate(directory, version)).resolves.toBe(true);
  });
});
