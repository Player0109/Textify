import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
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

// The speech check is the one CPU model and must work without a GPU:
// speech in whisper.cpp's JFK sample (16-bit mono PCM), none in silence.
const wav = readFileSync(".native/whisper/samples/jfk.wav");
let at = 12;
while (wav.toString("latin1", at, at + 4) !== "data")
  at += 8 + wav.readUInt32LE(at + 4);
const pcm = wav.subarray(at + 8, at + 8 + wav.readUInt32LE(at + 4));
const jfk = Buffer.alloc(4 + pcm.length * 2);
jfk.writeUInt32LE(pcm.length / 2);
for (let i = 0; i < pcm.length / 2; i++)
  jfk.writeFloatLE(pcm.readInt16LE(i * 2) / 32768, 4 + i * 4);
const silence = Buffer.alloc(4 + 32000 * 4);
silence.writeUInt32LE(32000);
const speech = spawnSync(
  resolve(
    `resources/textify-whisper${process.platform === "win32" ? ".exe" : ""}`,
  ),
  ["--speech", resolve("resources/ggml-silero-v5.1.2.bin")],
  {
    env: { ...process.env, GGML_VK_VISIBLE_DEVICES: "" },
    input: Buffer.concat([jfk, silence]),
    encoding: "utf8",
    timeout: 15000,
  },
);
assert.equal(speech.error, undefined);
assert.equal(speech.status, 0);
const [ready, heard, quiet] = speech.stdout
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line));
assert.deepEqual(ready, { ready: true });
assert.ok(heard.speech > 5);
assert.deepEqual(quiet, { speech: 0 });
console.log(
  `Speech check ran on the CPU without a GPU (${heard.speech} s in the sample).`,
);

// Expose the first Vulkan device, such as Linux runners' software renderer.
// The additional workers must still refuse it.
for (const name of ["transcribe", "audio"]) {
  const result = spawnSync(
    resolve(
      `resources/textify-${name}${process.platform === "win32" ? ".exe" : ""}`,
    ),
    ["must-not-load.gguf", "en"],
    {
      env: { ...process.env, GGML_VK_VISIBLE_DEVICES: "0" },
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
console.log("Additional workers also refused the unsupported or missing GPU.");
