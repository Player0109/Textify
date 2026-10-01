import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { requireGPU } from "../native/require-gpu.mjs";
const revision = "a8d002cfd879315632a579e73f0148d06959de36";
const expected =
  "7b17da903114ed45d82f48c030e3be6a5a8a279f884b2f733706dbb4e832fb6b";
await mkdir(".native", { recursive: true });
let archive;
try {
  archive = await readFile(".native/whisper.tar.gz");
} catch {
  const response = await fetch(
    `https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/${revision}`,
  );
  if (!response.ok) throw new Error("Pinned whisper.cpp download failed");
  archive = Buffer.from(await response.arrayBuffer());
}
if (createHash("sha256").update(archive).digest("hex") !== expected)
  throw new Error("whisper.cpp checksum mismatch");
await writeFile(".native/whisper.tar.gz", archive);
await rm(".native/whisper", { recursive: true, force: true });
await mkdir(".native/whisper");
const result = spawnSync(
  "tar",
  [
    "-xzf",
    ".native/whisper.tar.gz",
    "-C",
    ".native/whisper",
    "--strip-components=1",
  ],
  { stdio: "inherit" },
);
if (result.status !== 0) process.exit(result.status ?? 1);
await requireGPU(".native/whisper");
// Silero VAD v5.1.2 (MIT) in ggml format, for the speech check before transcription.
const speechModel = ".native/ggml-silero-v5.1.2.bin";
let model;
try {
  model = await readFile(speechModel);
} catch {
  const response = await fetch(
    "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin",
  );
  if (!response.ok) throw new Error("Pinned Silero speech model download failed");
  model = Buffer.from(await response.arrayBuffer());
}
if (
  createHash("sha256").update(model).digest("hex") !==
  "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf"
)
  throw new Error("Silero speech model checksum mismatch");
await writeFile(speechModel, model);
console.log(`Verified whisper.cpp ${revision}. Native builds now run offline.`);
const { prepareExtra } = await import("../native/prepare-extra.mjs");
await prepareExtra();
