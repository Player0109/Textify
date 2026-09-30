import { build } from "electron-builder";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { notaryCredentials, notarizeMacDmg } from "./mac-release.mjs";

const args = process.argv.slice(2);
const extra = args.filter((arg) => !["--preview", "--dir", "--publish", "never"].includes(arg));
if (extra.length) throw new Error(`Unsupported packaging option: ${extra.join(" ")}`);
const preview = args.includes("--preview");
const directory = args.includes("--dir");
const config = {};
let releaseIdentity;
if (process.platform === "darwin") {
  let identity = "-";
  // PR previews still need ad-hoc microphone entitlements; no signing key is used.
  if (preview) process.env.CSC_FOR_PULL_REQUEST = "true";
  if (!preview) {
    notaryCredentials();
    const listing = execFileSync("security", ["find-identity", "-v", "-p", "codesigning"], { encoding: "utf8" });
    const identities = [...listing.matchAll(/"(Developer ID Application:[^"\n]+)"/g)].map((match) => match[1]);
    const selected = identities.filter((name) => !process.env.CSC_NAME || name.includes(process.env.CSC_NAME));
    if (selected.length !== 1) {
      throw new Error(selected.length === 0
        ? "Install a valid Developer ID Application certificate with its private key in Keychain, then run packaging again. Ad-hoc local previews require npm run package:preview."
        : "Several Developer ID Application certificates are available. Set CSC_NAME to the intended certificate name so updates keep the same signing identity.");
    }
    releaseIdentity = selected[0];
    identity = releaseIdentity.replace(/^Developer ID Application:\s*/, "");
    // Stapling changes the DMG after electron-builder records it, so the DMG
    // stays out of the update feed. The updater installs the notarized ZIP.
    config.dmg = { sign: true, writeUpdateInfo: false };
    // Only signed Mac releases check for updates; Squirrel.Mac requires a
    // Developer ID signature, and Windows/Linux stay manual until signed.
    config.publish = { provider: "github", owner: "Player0109", repo: "Textify" };
  }
  config.forceCodeSigning = !preview;
  config.mac = {
    target: preview ? ["dmg"] : ["dmg", "zip"],
    identity,
    type: "distribution",
    entitlements: preview ? "native/entitlements.mac.plist" : "native/entitlements.mac.release.plist",
    entitlementsInherit: preview ? "native/entitlements.mac.plist" : "native/entitlements.mac.release.plist",
    notarize: !preview,
  };
}
// Packaging never publishes. Notarization uses electron-builder's optional local
// Keychain profile (APPLE_KEYCHAIN_PROFILE); credentials never enter the bundle.
const artifacts = await build({ dir: directory, publish: "never", config });
if (releaseIdentity && !directory) {
  const dmgs = artifacts.filter((file) => file.endsWith(".dmg"));
  if (dmgs.length !== 1) throw new Error("Expected exactly one production Mac DMG.");
  notarizeMacDmg(resolve(dmgs[0]), releaseIdentity);
  console.log("Final DMG signature, notarization, staple, and Gatekeeper assessment passed.");
}
