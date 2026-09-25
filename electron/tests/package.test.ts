import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const packageURL = pathToFileURL(resolve("scripts/package.mjs")).href;
const helperURL = pathToFileURL(resolve("scripts/mac-release.mjs")).href;
const authority = "Developer ID Application: Release Test (ABC1234567)";
const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform")!;
const originalArgv = process.argv;
const build = vi.fn();
const execFileSync = vi.fn();
const notarizeMacDmg = vi.fn();

beforeEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  vi.stubEnv("CSC_NAME", "");
  vi.stubEnv("CSC_FOR_PULL_REQUEST", "");
  Object.defineProperty(process, "platform", { value: "darwin" });
  process.argv = ["node", "scripts/package.mjs"];
  build.mockResolvedValue(["release/Textify-test-mac-arm64.dmg"]);
  execFileSync.mockReturnValue(`1) ABCDEF "${authority}"\n1 valid identities found`);
  vi.doMock("electron-builder", () => ({ build }));
  vi.doMock("node:child_process", () => ({ execFileSync }));
  vi.doMock(helperURL, () => ({ notaryCredentials: vi.fn(), notarizeMacDmg }));
});

afterEach(() => {
  Object.defineProperty(process, "platform", originalPlatform);
  process.argv = originalArgv;
  vi.unstubAllEnvs();
  vi.doUnmock("electron-builder");
  vi.doUnmock("node:child_process");
  vi.doUnmock(helperURL);
});

describe("Mac packaging identity", () => {
  it("passes the builder an unprefixed qualifier and verifies the full DMG authority", async () => {
    await import(packageURL);
    expect(build).toHaveBeenCalledWith(expect.objectContaining({
      publish: "never",
      config: expect.objectContaining({
        forceCodeSigning: true,
        mac: expect.objectContaining({ identity: "Release Test (ABC1234567)", notarize: true }),
      }),
    }));
    expect(notarizeMacDmg).toHaveBeenCalledWith(resolve("release/Textify-test-mac-arm64.dmg"), authority);
  });

  it("keeps pull-request previews ad-hoc without notarization or publication", async () => {
    process.argv.push("--preview", "--dir");
    await import(packageURL);
    expect(build).toHaveBeenCalledWith(expect.objectContaining({
      dir: true,
      publish: "never",
      config: expect.objectContaining({
        forceCodeSigning: false,
        mac: expect.objectContaining({ identity: "-", notarize: false }),
      }),
    }));
    expect(process.env.CSC_FOR_PULL_REQUEST).toBe("true");
    expect(execFileSync).not.toHaveBeenCalled();
    expect(notarizeMacDmg).not.toHaveBeenCalled();
  });
});
