import { spawnSync } from "node:child_process";
import { readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";

const app = resolve(process.argv[2]);
const frameworks = join(app, "Contents/Frameworks");
const helpers = (await readdir(frameworks)).filter((name) => name.endsWith(".app") && name.includes("Helper"));
assert.ok(helpers.length);
for (const bundle of [app, ...helpers.map((name) => join(frameworks, name))]) {
  const signature = spawnSync("codesign", ["-d", "--entitlements", ":-", bundle], { encoding: "utf8" });
  assert.equal(signature.status, 0);
  const json = spawnSync("plutil", ["-convert", "json", "-o", "-", "-"], { input: signature.stdout, encoding: "utf8" });
  assert.equal(json.status, 0);
  assert.equal(JSON.parse(json.stdout)["com.apple.security.device.audio-input"], true,
    `${bundle} must be signed with microphone input capability`);
}
console.log("Main app and every Electron helper have the signed Audio Input entitlement.");
