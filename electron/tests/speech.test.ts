import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, it } from "vitest";
import { speechSeconds } from "../src/main/speech";

const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const dispose of cleanup.splice(0)) await dispose();
});
// A stand-in for textify-whisper --speech: it reads one recording and replies
// with the given lines, where "count" becomes the recording's length in seconds.
async function detector(replies: object[]) {
  const dir = await mkdtemp(join(tmpdir(), "textify-speech-"));
  const script = join(dir, "speech.cjs");
  await writeFile(
    script,
    `
    let input = Buffer.alloc(0);
    process.stdin.on("data", (chunk) => (input = Buffer.concat([input, chunk])));
    process.stdin.on("end", () => {
      const count = input.readUInt32LE(0);
      if (input.length !== 4 + count * 4) process.exit(1);
      for (const reply of ${JSON.stringify(replies)})
        console.log(JSON.stringify(reply.speech === "count" ? { speech: count / 16000 } : reply));
    });
  `,
  );
  cleanup.push(() => rm(dir, { recursive: true }));
  return script;
}
it("returns the seconds of speech the detector reports", async () => {
  const script = await detector([{ ready: true }, { speech: "count" }]);
  expect(
    await speechSeconds(process.execPath, [script], new Float32Array(8000)),
  ).toBe(0.5);
});
it.each([
  [[{ error: "speech_model" }]],
  [[{ ready: true }, { error: "speech_detection" }]],
  [[{ ready: true }, { speech: -1 }]],
  [[{ ready: true }]],
])("rejects a failed or malformed check: %j", async (replies) => {
  const script = await detector(replies);
  await expect(
    speechSeconds(process.execPath, [script], new Float32Array(8000)),
  ).rejects.toThrow("speech_check");
});
it("rejects when the detector cannot start", async () => {
  await expect(
    speechSeconds(join(tmpdir(), "missing-textify-whisper"), [], new Float32Array(8000)),
  ).rejects.toThrow("speech_check");
});
