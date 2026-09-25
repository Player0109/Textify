import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";

const helperURL = pathToFileURL(resolve("scripts/mac-release.mjs")).href;
const { notaryCredentials, notarizeMacDmg, verifyProductionInstallers } = await import(helperURL);
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
    const files = ["mac-arm64.dmg", "win-x64.exe", "linux-x64.AppImage", "linux-x64.deb"]
      .map((suffix) => `Textify-test-${suffix}`);
    expect(() => verifyProductionInstallers(files.slice(1), "test", "darwin", commands().run))
      .toThrow("Missing release installer");
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
