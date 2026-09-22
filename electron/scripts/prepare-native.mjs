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
console.log(`Verified whisper.cpp ${revision}. Native builds now run offline.`);
