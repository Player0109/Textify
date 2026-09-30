import { build } from "esbuild";
import { createRequire } from "node:module";
import { readFile, stat } from "node:fs/promises";
import { resolve, basename } from "node:path";
import assert from "node:assert/strict";

const [path, language = "en", pcmPath] = process.argv.slice(2);
if (!path || !["en", "hi", "zh"].includes(language))
  throw new Error(
    "Usage: node scripts/runtime-smoke.mjs MODEL [en|hi|zh] [mono-16khz-f32-file]",
  );
await build({
  stdin: {
    contents:
      'export { WhisperWorker } from "./src/main/worker"; export { LivePreview } from "./src/core/live-preview"; export { verifyCatalog, hashFile, catalogModels } from "./src/main/models";',
    resolveDir: process.cwd(),
  },
  bundle: true,
  platform: "node",
  format: "cjs",
  outfile: ".native/runtime-smoke.cjs",
});
const { WhisperWorker, LivePreview, verifyCatalog, hashFile, catalogModels } =
  createRequire(import.meta.url)(resolve(".native/runtime-smoke.cjs"));
const models = catalogModels(
  verifyCatalog(
    await readFile("resources/manifest.json"),
    await readFile("resources/manifest.json.sig"),
  ),
  verifyCatalog(
    await readFile("resources/extra-models/manifest.json"),
    await readFile("resources/extra-models/manifest.json.sig"),
  ),
);
const directory = (await stat(path)).isDirectory();
const model = models.find(
  (model) =>
    (directory && model.directory) ||
    (!directory &&
      (model.file.filename === basename(path) ||
        `${model.id}.${model.engine === "whisper_cpp" ? "bin" : "gguf"}` ===
          basename(path))),
);
assert.ok(
  model?.languages.includes(language),
  "The signed catalog must support the requested model and language",
);
for (const file of model.files)
  assert.equal(
    await hashFile(directory ? resolve(path, file.filename) : path),
    file.sha256,
    "Use the exact signed artifact",
  );
let samples;
if (pcmPath) {
  const bytes = await readFile(pcmPath);
  assert.equal(bytes.length % 4, 0);
  samples = Float32Array.from({ length: bytes.length / 4 }, (_, i) =>
    bytes.readFloatLE(i * 4),
  );
} else {
  assert.equal(language, "en", "A Hindi PCM fixture is required");
  const wav = await readFile(".native/whisper/samples/jfk.wav");
  let offset = 12;
  while (wav.toString("ascii", offset, offset + 4) !== "data")
    offset +=
      8 + wav.readUInt32LE(offset + 4) + (wav.readUInt32LE(offset + 4) % 2);
  const count = wav.readUInt32LE(offset + 4) / 2;
  samples = Float32Array.from(
    { length: count },
    (_, i) => wav.readInt16LE(offset + 8 + i * 2) / 32768,
  );
}
const worker = new WhisperWorker(
  resolve(
    `resources/textify-whisper${process.platform === "win32" ? ".exe" : ""}`,
  ),
  () => {},
);
try {
  await worker.load(resolve(path), language, ["Textify"], model.engine);
  assert.ok(worker.gpu?.device);
  console.log(`GPU: ${worker.gpu.device} (${worker.gpu.backend})`);
  if (process.env.TEXTIFY_STREAMING_SMOKE === "1") {
    assert.equal(worker.streaming, true);
    await worker.beginStream();
    let live = "",
      updates = 0,
      first = null;
    const started = performance.now();
    for (let offset = 0; offset < samples.length; offset += 5120) {
      const delta = await worker.pushStream(
        samples.subarray(offset, offset + 5120),
      );
      if (delta) {
        live += delta;
        updates++;
        first ??= performance.now() - started;
      }
    }
    assert.ok(updates > 1, "Text must arrive before finalization");
    assert.ok(
      language === "en"
        ? /fellow Americans/i.test(live)
        : /[\u4e00-\u9fff]/u.test(live),
    );
    assert.ok((await worker.finishStream()).trim());
    await worker.resetStream();
    // Cancel/reset a second stream, then verify ordinary final recognition still works.
    await worker.beginStream();
    await worker.pushStream(samples.subarray(0, 5120));
    await worker.resetStream();
    console.log(
      `Streaming: ${updates} nonempty deltas, first at ${Math.round(first)} ms of accelerated fixture replay; finish and reset passed.`,
    );
  }
  if (process.env.TEXTIFY_LONG_STREAMING_SMOKE === "1") {
    assert.equal(worker.streaming, true);
    let starts = 0,
      updates = 0,
      afterReset = 0;
    const started = performance.now();
    let first = null;
    const preview = new LivePreview(
      {
        beginStream: async () => {
          starts++;
          await worker.beginStream();
        },
        pushStream: (pcm) => worker.pushStream(pcm),
        finishStream: () => worker.finishStream(),
        resetStream: () => worker.resetStream(),
      },
      (text) => {
        if (text.trim()) {
          updates++;
          first ??= performance.now() - started;
          if (starts > 1) afterReset++;
        }
      },
    );
    try {
      for (let offset = 0; offset < 32 * 16000; offset += 5120) {
        const frame = Float32Array.from(
          { length: 5120 },
          (_, i) => samples[(offset + i) % samples.length],
        );
        preview.push(frame);
        frame.fill(0);
        await new Promise((resolve) => setTimeout(resolve, 320));
      }
    } finally {
      await preview.stop();
    }
    assert.equal(
      starts,
      2,
      "The actual decoder must restart after its 25-second window",
    );
    assert.ok(
      updates > 1 && afterReset > 0,
      "Live text must continue after the reset",
    );
    console.log(
      `Paced 32-second preview passed: ${updates} updates, first at ${Math.round(first)} ms including audio arrival, ${afterReset} after window reset. Not a general latency benchmark.`,
    );
  }
  const text = await worker.transcribe(samples);
  assert.ok(
    text &&
      (language === "hi"
        ? /नमस्ते|हिंदी|मौसम/u
        : language === "zh"
          ? /[\u4e00-\u9fff]/u
          : /fellow Americans/i
      ).test(text),
    "Fixture recognition failed",
  );
  console.log(
    `${model.name} (${language}): verified artifact, GPU worker startup and fixture recognition passed. Output was not saved.`,
  );
} finally {
  samples.fill(0);
  worker.stop();
}
