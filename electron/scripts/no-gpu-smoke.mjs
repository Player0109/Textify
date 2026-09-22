import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import assert from "node:assert/strict";
// Hide all Vulkan devices, exercising the real shipping worker, not a CPU mode.
const result = spawnSync(
  resolve(
    `resources/textify-whisper${process.platform === "win32" ? ".exe" : ""}`,
  ),
  [resolve(".native/must-not-load-model.bin")],
  {
    env: { ...process.env, GGML_VK_VISIBLE_DEVICES: "" },
    encoding: "utf8",
    timeout: 15000,
  },
);
assert.equal(result.error, undefined);
assert.equal(result.status, 1);
assert.deepEqual(JSON.parse(result.stdout), { error: "gpu_unavailable" });
console.log(
  "Shipping worker refused startup without a GPU before attempting model load.",
);
