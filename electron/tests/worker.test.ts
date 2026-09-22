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
