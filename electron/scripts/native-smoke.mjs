import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import assert from "node:assert/strict";
const model = process.argv[2],
  sample = process.argv[3] || ".native/whisper/samples/jfk.wav";
if (!model)
  throw new Error(
    "Usage: node scripts/native-smoke.mjs /path/to/verified/model.bin [public-sample.wav]",
  );
const wav = await readFile(sample);
assert.equal(wav.toString("ascii", 0, 4), "RIFF");
let pcm;
for (let at = 12; at + 8 <= wav.length; ) {
  const size = wav.readUInt32LE(at + 4),
    tag = wav.toString("ascii", at, at + 4);
  if (tag === "fmt ") {
    assert.equal(wav.readUInt16LE(at + 8), 1);
    assert.equal(wav.readUInt16LE(at + 10), 1);
    assert.equal(wav.readUInt32LE(at + 12), 16000);
    assert.equal(wav.readUInt16LE(at + 22), 16);
  }
  if (tag === "data") pcm = wav.subarray(at + 8, at + 8 + size);
  at += 8 + size + (size % 2);
}
assert.ok(pcm);
const worker = spawn(
  resolve(
    `resources/textify-whisper${process.platform === "win32" ? ".exe" : ""}`,
  ),
  [resolve(model)],
  { stdio: "pipe" },
);
worker.stderr.resume();
const timeout = setTimeout(() => worker.kill(), 120000);
try {
  let ready = false,
    result;
  for await (const line of createInterface({ input: worker.stdout })) {
    const message = JSON.parse(line);
    if (message.ready) {
      ready = true;
      const count = pcm.length / 2,
        data = Buffer.alloc(4 + count * 4);
      data.writeUInt32LE(count);
      for (let i = 0; i < count; i++)
        data.writeFloatLE(pcm.readInt16LE(i * 2) / 32768, 4 + i * 4);
      worker.stdin.write(data, () => data.fill(0));
    } else {
      result = message;
      worker.stdin.end();
      break;
    }
  }
  assert.ok(ready);
  assert.match(result?.text ?? "", /fellow Americans/i);
  assert.ok(Number.isFinite(result.averageLogProbability));
  console.log(
    "Real native worker recognized the public JFK sample from in-memory PCM. No audio or transcript files written.",
  );
} finally {
  clearTimeout(timeout);
  worker.kill();
}
