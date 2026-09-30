import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";

const helperURL = pathToFileURL(resolve("scripts/mac-release.mjs")).href;
const { macUpdateFeed, notaryCredentials, notarizeMacDmg, verifyMacUpdate, verifyProductionInstallers } = await import(helperURL);
const identity = "Developer ID Application: Release Test (ABC1234567)";
const dmg = "/release/Textify-test-mac-arm64.dmg";
const credentials = { APPLE_KEYCHAIN_PROFILE: "test-notary" };

function commands({ authority = identity, status = "Accepted", fail = "" } = {}) {
  const calls: string[][] = [];
  const run = (command: string, args: string[]) => {
    calls.push([command, ...args]);
    if ([command, ...args].join(" ").includes(fail) && fail) throw new Error("tool rejected artifact");
    if (args[0] === "--display")
      return { stdout: "", stderr: `Authority=${authority}\nTeamIdentifier=ABC1234567\n` };
    return { stdout: JSON.stringify({ status }), stderr: "" };
  };
  return { calls, run };
}

describe("production Mac release gates", () => {
  it("accepts each existing local credential method and rejects incomplete credentials", () => {
    expect(notaryCredentials({ ...credentials, APPLE_KEYCHAIN: "/test.keychain" }))
      .toEqual(["--keychain-profile", "test-notary", "--keychain", "/test.keychain"]);
    expect(notaryCredentials({ APPLE_ID: "test@example.invalid", APPLE_APP_SPECIFIC_PASSWORD: "test-password", APPLE_TEAM_ID: "ABC1234567", ...credentials }))
      .toEqual(["--apple-id", "test@example.invalid", "--password", "test-password", "--team-id", "ABC1234567"]);
    expect(notaryCredentials({ APPLE_API_KEY: "/test.p8", APPLE_API_KEY_ID: "TEST", APPLE_API_ISSUER: "test-issuer" }))
      .toEqual(["--key", "/test.p8", "--key-id", "TEST", "--issuer", "test-issuer"]);
    expect(() => notaryCredentials({})).toThrow("Configure a local notarytool");
    expect(() => notaryCredentials({ APPLE_ID: "test@example.invalid", ...credentials }))
      .toThrow("Apple ID notarization requires");
  });

  it("submits the signed DMG, then staples, validates and assesses the final bytes", () => {
    const { calls, run } = commands();
    notarizeMacDmg(dmg, identity, credentials, run);
    expect(calls[2]).toEqual(["xcrun", "notarytool", "submit", dmg, "--keychain-profile", "test-notary", "--wait", "--output-format", "json"]);
    expect(calls[3]).toEqual(["xcrun", "stapler", "staple", dmg]);
    expect(calls.at(-2)).toEqual(["xcrun", "stapler", "validate", dmg]);
    expect(calls.at(-1)).toEqual(["spctl", "--assess", "--verbose", "--type", "open", "--context", "context:primary-signature", dmg]);
  });

  it.each(["Apple Development: Test", "Developer ID Application: Other (ABC1234567)"])
    ("rejects a wrong signing authority before submission: %s", (authority) => {
      const { calls, run } = commands({ authority });
      expect(() => notarizeMacDmg(dmg, identity, credentials, run)).toThrow("selected Developer ID");
      expect(calls.some((call) => call.includes("submit"))).toBe(false);
    });

  it.each(["Invalid", "In Progress"])("does not staple a %s submission", (status) => {
    const { calls, run } = commands({ status });
    expect(() => notarizeMacDmg(dmg, identity, credentials, run)).toThrow("did not accept");
    expect(calls.some((call) => call.includes("staple"))).toBe(false);
  });

  it.each(["stapler staple", "stapler validate", "spctl --assess"])
    ("fails the release when %s fails", (fail) => {
      expect(() => notarizeMacDmg(dmg, identity, credentials, commands({ fail }).run))
        .toThrow("tool rejected artifact");
    });

  it("requires every requested platform installer and rechecks the DMG before checksums", () => {
    const files = ["mac-arm64.dmg", "mac-arm64.zip", "win-x64.exe", "linux-x86_64.AppImage", "linux-amd64.deb"]
      .map((suffix) => `Textify-test-${suffix}`);
    expect(() => verifyProductionInstallers(files.slice(1), "test", "darwin", commands().run))
      .toThrow("Missing release installer");
    expect(() => verifyProductionInstallers(files.filter((file) => !file.endsWith(".zip")), "test", "darwin", commands().run))
      .toThrow("Missing release installer: Textify-test-mac-arm64.zip");
    expect(() => verifyProductionInstallers(files.map((file) => file.replace(/linux-(x86_64|amd64)/, "linux-x64")), "test", "darwin", commands().run))
      .toThrow("Missing release installer: Textify-test-linux-x86_64.AppImage");
    expect(() => verifyProductionInstallers(files, "test", "linux", commands().run))
      .toThrow("maintainer Mac");
    expect(() => verifyProductionInstallers(files, "test", "darwin", commands({ authority: "adhoc" }).run))
      .toThrow("Developer ID");
    const { calls, run } = commands();
    verifyProductionInstallers(files, "test", "darwin", run);
    expect(calls.some((call) => call.includes("validate"))).toBe(true);
    expect(calls.at(-1)?.[0]).toBe("spctl");
  });
});

describe("Mac update feed", () => {
  const version = "0.2.0-preview.24";
  const zip = `Textify-${version}-mac-arm64.zip`;
  const bytes = Buffer.from("notarized app archive");
  const sha512 = createHash("sha512").update(bytes).digest("base64");
  const feed = (overrides: Partial<Record<"version" | "url" | "sha512" | "size", string>> = {}) => {
    const value = { version, url: zip, sha512, size: String(bytes.length), ...overrides };
    return [
      `version: ${value.version}`,
      "files:",
      `  - url: ${value.url}`,
      `    sha512: ${value.sha512}`,
      `    size: ${value.size}`,
      "    blockMapSize: 1234",
      `path: ${value.url}`,
      `sha512: ${value.sha512}`,
      "releaseDate: '2026-10-01T00:00:00.000Z'",
      "",
    ].join("\n");
  };
  async function release(text: string) {
    const directory = await mkdtemp(join(tmpdir(), "textify-feed-test-"));
    await writeFile(join(directory, zip), bytes);
    await writeFile(join(directory, "preview-mac.yml"), text);
    return directory;
  }

  it("uses electron-builder's channel feed name", () => {
    expect(macUpdateFeed("0.2.0-preview.24")).toBe("preview-mac.yml");
    expect(macUpdateFeed("1.0.0")).toBe("latest-mac.yml");
  });

  it("accepts a feed for the exact ZIP and checks the app inside it", async () => {
    const directory = await release(feed());
    const { calls, run } = commands();
    try {
      await verifyMacUpdate(directory, version, run);
    } finally {
      await rm(directory, { recursive: true });
    }
    expect(calls[0].slice(0, 4)).toEqual(["ditto", "-x", "-k", join(directory, zip)]);
    const app = join(calls[0][4], "Textify.app");
    expect(calls).toContainEqual(["codesign", "--verify", "--deep", "--strict", app]);
    expect(calls).toContainEqual(["xcrun", "stapler", "validate", app]);
    expect(calls.at(-1)).toEqual(["spctl", "--assess", "--verbose", "--type", "execute", app]);
  });

  it.each([
    [{ version: "0.2.0-preview.23" }, "package version"],
    [{ url: "Textify-0.2.0-preview.24-mac-arm64.dmg" }, "must list only"],
    [{ sha512: "stale" }, "final ZIP bytes"],
    [{ size: "1" }, "final ZIP bytes"],
  ])("rejects a feed that does not match the release: %o", async (overrides, message) => {
    const directory = await release(feed(overrides));
    const { calls, run } = commands();
    try {
      await expect(verifyMacUpdate(directory, version, run)).rejects.toThrow(message);
    } finally {
      await rm(directory, { recursive: true });
    }
    expect(calls).toEqual([]);
  });

  it("rejects an app in the ZIP that is not Developer ID signed", async () => {
    const directory = await release(feed());
    try {
      await expect(verifyMacUpdate(directory, version, commands({ authority: "adhoc" }).run))
        .rejects.toThrow("Developer ID");
    } finally {
      await rm(directory, { recursive: true });
    }
  });
});
