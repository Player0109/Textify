import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, it } from "vitest";
import { WhisperWorker } from "../src/main/worker";

const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const dispose of cleanup.splice(0)) await dispose();
});
async function fixture(message: object) {
  const dir = await mkdtemp(join(tmpdir(), "textify-worker-"));
  const script = join(dir, "worker.cjs");
  await writeFile(
    script,
    `process.stdin.resume(); console.log(${JSON.stringify(JSON.stringify(message))});`,
  );
  const worker = new WhisperWorker(process.execPath, () => {});
  cleanup.push(async () => {
    worker.stop();
    await rm(dir, { recursive: true });
  });
  return { worker, script };
}
it("refuses a ready worker that has not confirmed a hardware GPU", async () => {
  const { worker, script } = await fixture({ ready: true });
  await expect(worker.load(script)).rejects.toThrow("gpu_unavailable");
  expect(worker.ready).toBe(false);
});
it.each(["gpu_unavailable", "gpu_init", "gpu_model_load", "gpu_inference"])(
  "preserves safe %s errors from the native worker",
  async (error) => {
    const { worker, script } = await fixture({ error });
    await expect(worker.load(script)).rejects.toThrow(error);
    expect(worker.ready).toBe(false);
  },
);
it("accepts a confirmed GPU and clears it when stopped", async () => {
  const gpu = { backend: "Vulkan", device: "NVIDIA test device" };
  const { worker, script } = await fixture({ ready: true, gpu });
  await worker.load(script);
  expect(worker.ready).toBe(true);
  expect(worker.gpu).toEqual(gpu);
  worker.stop();
  expect(worker.gpu).toBeNull();
});
it("starts the native worker with AMD's switchable-graphics Vulkan layer disabled", async () => {
  const dir = await mkdtemp(join(tmpdir(), "textify-worker-env-"));
  const script = join(dir, "worker.cjs");
  await writeFile(
    script,
    `process.stdin.resume(); console.log(JSON.stringify({ready: true, gpu: {backend: "Vulkan", device: "layer disabled: " + process.env.DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1}}));`,
  );
  const worker = new WhisperWorker(process.execPath, () => {});
  cleanup.push(async () => {
    worker.stop();
    await rm(dir, { recursive: true });
  });
  await worker.load(script);
  expect(worker.gpu?.device).toBe("layer disabled: 1");
});

it.each(["transcribe_cpp", "audio_cpp"] as const)(
  "accepts %s text without inventing Whisper confidence scores",
  async (engine) => {
    const dir = await mkdtemp(join(tmpdir(), "textify-worker-protocol-"));
    const script = join(dir, "worker.cjs");
    await writeFile(
      script,
      `
    let input = Buffer.alloc(0), configured = false;
    process.stdin.on("data", chunk => {
      input = Buffer.concat([input, chunk]);
      while (input.length >= 4) {
        const size = input.readUInt32LE(0) * (configured ? 4 : 1);
        if (input.length < size + 4) return;
        input = input.subarray(size + 4);
        console.log(JSON.stringify(configured ? {text: "A valid sentence."} : {ready: true, gpu: {backend: "Metal", device: "Test GPU"}}));
        configured = true;
      }
    });
  `,
    );
    const worker = new WhisperWorker(process.execPath, () => {});
    cleanup.push(async () => {
      worker.stop();
      await rm(dir, { recursive: true });
    });
    await worker.load(script, "en", [], engine);
    expect(await worker.transcribe(new Float32Array(16000))).toBe(
      "A valid sentence.",
    );
  },
);
