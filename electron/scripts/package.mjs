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
    identity = selected[0];
    releaseIdentity = identity;
    // Stapling changes the final bytes; automatic updates/blockmaps are deferred.
    config.dmg = { sign: true, writeUpdateInfo: false };
  }
  config.forceCodeSigning = !preview;
  config.mac = {
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
