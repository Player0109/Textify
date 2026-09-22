import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import assert from "node:assert/strict";
// Hide Vulkan devices. Hosted Mac's paravirtual Metal device lacks Apple7
// compute support. Both must be refused by the real shipping worker.
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

if (process.platform === "darwin") {
  for (const name of ["transcribe", "audio"]) {
    const result = spawnSync(
      resolve(`resources/textify-${name}`),
      ["must-not-load.gguf", "en"],
      {
        input: Buffer.alloc(4),
        timeout: 15000,
      },
    );
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1);
    assert.deepEqual(JSON.parse(result.stdout.toString()), {
      error: "gpu_unavailable",
    });
  }
  console.log(
    "Additional Metal workers also refused the unsupported virtual GPU.",
  );
}
