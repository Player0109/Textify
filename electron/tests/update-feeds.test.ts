import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const { feedName, verifyUpdateFeed } =
  await import(pathToFileURL(resolve("scripts/update-feeds.mjs")).href);
const version = "0.2.0-preview.24";
const appImage = `Textify-${version}-linux-x86_64.AppImage`;
const deb = `Textify-${version}-linux-amd64.deb`;
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
