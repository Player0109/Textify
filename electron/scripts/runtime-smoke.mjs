import { build } from "esbuild";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { resolve, basename } from "node:path";
import assert from "node:assert/strict";

const [path, language = "en", pcmPath] = process.argv.slice(2);
if (!path || !["en", "hi"].includes(language))
  throw new Error(
    "Usage: node scripts/runtime-smoke.mjs MODEL [en|hi] [mono-16khz-f32-file]",
  );
await build({
  stdin: {
    contents:
      'export { WhisperWorker } from "./src/main/worker"; export { verifyCatalog, hashFile, catalogModels } from "./src/main/models";',
    resolveDir: process.cwd(),
  },
  bundle: true,
  platform: "node",
  format: "cjs",
  outfile: ".native/runtime-smoke.cjs",
});
const { WhisperWorker, verifyCatalog, hashFile, catalogModels } = createRequire(
  import.meta.url,
)(resolve(".native/runtime-smoke.cjs"));
const models = catalogModels(
  verifyCatalog(
    await readFile("resources/manifest.json"),
    await readFile("resources/manifest.json.sig"),
  ),
);
const model = models.find((model) => model.file.filename === basename(path));
assert.ok(
  model?.languages.includes(language),
  "The signed catalog must support the requested model and language",
);
assert.equal(
  await hashFile(path),
  model.file.sha256,
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
  await worker.load(resolve(path), language, ["Textify"]);
  const text = await worker.transcribe(samples);
  assert.ok(
    text &&
      (language === "hi" ? /नमस्ते|हिंदी|मौसम/u : /fellow Americans/i).test(
        text,
      ),
    "Fixture recognition failed",
  );
  console.log(
    `${model.name} (${language}): verified artifact, worker startup with custom vocabulary, and fixture recognition passed. Output was not saved.`,
  );
} finally {
  samples.fill(0);
  worker.stop();
}
