import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

export function notaryCredentials(env = process.env) {
  // Match electron-builder's credential precedence for the app submission.
  if (env.APPLE_ID || env.APPLE_APP_SPECIFIC_PASSWORD) {
    if (!env.APPLE_ID || !env.APPLE_APP_SPECIFIC_PASSWORD || !env.APPLE_TEAM_ID)
      throw new Error("Apple ID notarization requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD and APPLE_TEAM_ID.");
    return ["--apple-id", env.APPLE_ID, "--password", env.APPLE_APP_SPECIFIC_PASSWORD, "--team-id", env.APPLE_TEAM_ID];
  }
  if (env.APPLE_API_KEY || env.APPLE_API_KEY_ID || env.APPLE_API_ISSUER) {
    if (!env.APPLE_API_KEY || !env.APPLE_API_KEY_ID || !env.APPLE_API_ISSUER)
      throw new Error("API notarization requires APPLE_API_KEY, APPLE_API_KEY_ID and APPLE_API_ISSUER.");
    return ["--key", env.APPLE_API_KEY, "--key-id", env.APPLE_API_KEY_ID, "--issuer", env.APPLE_API_ISSUER];
  }
  if (env.APPLE_KEYCHAIN_PROFILE)
    return ["--keychain-profile", env.APPLE_KEYCHAIN_PROFILE,
      ...(env.APPLE_KEYCHAIN ? ["--keychain", env.APPLE_KEYCHAIN] : [])];
  throw new Error("Configure a local notarytool Keychain profile (APPLE_KEYCHAIN_PROFILE) or complete Apple notarization credentials before packaging a distributable Mac app.");
}

function runMacTool(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  // Child-process errors can contain command arguments, including credentials.
  if (result.error || result.status !== 0)
    throw new Error(`${command} ${args[0]} failed; release verification stopped. Inspect this step locally without sharing credentials.`);
  return result;
}

function verifyDeveloperId(dmg, run, identity) {
  run("codesign", ["--verify", "--strict", dmg]);
  const result = run("codesign", ["--display", "--verbose=4", dmg]);
  const signature = `${result.stdout}\n${result.stderr}`;
  if (!/^Authority=Developer ID Application:.+$/m.test(signature) ||
      !/^TeamIdentifier=[A-Z0-9]{10}$/m.test(signature) ||
      (identity && !signature.split(/\r?\n/).includes(`Authority=${identity}`)))
    throw new Error("The DMG must be signed with the selected Developer ID Application identity.");
}

export function verifyMacDmg(dmg, run = runMacTool) {
  verifyDeveloperId(dmg, run);
  run("xcrun", ["stapler", "validate", dmg]);
  run("spctl", ["--assess", "--verbose", "--type", "open", "--context", "context:primary-signature", dmg]);
}

export function notarizeMacDmg(dmg, identity, env = process.env, run = runMacTool) {
  verifyDeveloperId(dmg, run, identity);
  const result = run("xcrun", ["notarytool", "submit", dmg, ...notaryCredentials(env), "--wait", "--output-format", "json"]);
  let submission;
  try { submission = JSON.parse(result.stdout); }
  catch { throw new Error("Apple returned an invalid notarization response; the DMG is not ready for release."); }
  if (submission.status !== "Accepted")
    throw new Error("Apple did not accept the DMG notarization; the DMG is not ready for release.");
  run("xcrun", ["stapler", "staple", dmg]);
  verifyMacDmg(dmg, run);
}

export function verifyProductionInstallers(files, version, platform = process.platform, run = runMacTool) {
  if (platform !== "darwin")
    throw new Error("Assemble production checksums on the maintainer Mac so the DMG can be verified.");
  for (const suffix of ["mac-arm64.dmg", "win-x64.exe", "linux-x64.AppImage", "linux-x64.deb"]) {
    if (!files.includes(`Textify-${version}-${suffix}`))
      throw new Error(`Missing release installer: Textify-${version}-${suffix}`);
  }
  for (const file of files.filter((name) => name.endsWith(".dmg")))
    verifyMacDmg(resolve("release", file), run);
}
