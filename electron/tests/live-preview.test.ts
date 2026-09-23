import { expect, it, vi } from "vitest";
import { LivePreview } from "../src/core/live-preview";

const tick = () => new Promise((resolve) => setImmediate(resolve));
function fixture() {
  const ports = {
    beginStream: vi.fn(async () => {}),
    pushStream: vi.fn(async (_samples: Float32Array) => " hello"),
    finishStream: vi.fn(async () => "window one"),
    resetStream: vi.fn(async () => {}),
  };
  const changed = vi.fn();
  return { ports, changed, preview: new LivePreview(ports, changed) };
}
it("buffers short microphone frames and appends exact token deltas", async () => {
  const h = fixture();
  h.ports.pushStream
    .mockResolvedValueOnce("Hel")
    .mockResolvedValueOnce("lo, 世界");
  for (let i = 0; i < 16; i++) h.preview.push(new Float32Array(320).fill(0.1));
  await tick();
  h.preview.push(new Float32Array(5120).fill(0.1));
  await tick();
  expect(h.changed.mock.calls.map(([text]) => text)).toEqual([
    "Hel",
    "Hello, 世界",
  ]);
  await h.preview.stop();
  expect(h.ports.resetStream).toHaveBeenCalledOnce();
  expect(
    h.ports.pushStream.mock.calls.every(([samples]) =>
      samples.every((x) => x === 0),
    ),
  ).toBe(true);
});
it("drains in-flight inference before reset and ignores its late text after cancellation", async () => {
  const h = fixture();
  let resolve!: (text: string) => void;
  h.ports.pushStream.mockImplementationOnce(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  h.preview.push(new Float32Array(16000));
  await tick();
  const stopping = h.preview.stop();
  expect(h.ports.resetStream).not.toHaveBeenCalled();
  resolve("stale");
  await stopping;
  expect(h.changed).not.toHaveBeenCalled();
  expect(h.ports.pushStream).toHaveBeenCalledOnce();
  expect(h.ports.resetStream).toHaveBeenCalledOnce();
  await h.preview.stop();
  expect(h.ports.resetStream).toHaveBeenCalledOnce();
});
it("rolls the native decoder at 25 seconds without losing preview continuity", async () => {
  const h = fixture();
  h.preview.push(new Float32Array(400000));
  await tick();
  h.preview.push(new Float32Array(5120));
  await tick();
  expect(h.ports.finishStream).toHaveBeenCalledOnce();
  expect(h.ports.beginStream).toHaveBeenCalledTimes(2);
  expect(h.changed).toHaveBeenLastCalledWith("window one  hello");
  expect(
    h.ports.pushStream.mock.calls.reduce((n, [pcm]) => n + pcm.length, 0),
  ).toBe(405120);
  await h.preview.stop();
});
it("bounds a slow preview queue and resets before using newer audio", async () => {
  const h = fixture();
  let resolve!: (text: string) => void;
  h.ports.pushStream.mockImplementationOnce(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  h.preview.push(new Float32Array(5120));
  await tick();
  h.preview.push(new Float32Array(800000).fill(0.2));
  resolve("stale window");
  await tick();
  expect(h.ports.beginStream).toHaveBeenCalledTimes(2);
  expect(h.changed.mock.calls.some(([text]) => text.includes("stale"))).toBe(
    false,
  );
  expect(
    h.ports.pushStream.mock.calls.reduce((n, [pcm]) => n + pcm.length, 0),
  ).toBeLessThanOrEqual(405120);
  await h.preview.stop();
});
it("surfaces inference failure and releases preview buffers", async () => {
  const h = fixture();
  h.ports.pushStream.mockRejectedValueOnce(new Error("gpu_inference"));
  h.preview.push(new Float32Array(5120));
  await tick();
  await expect(h.preview.stop()).rejects.toThrow("gpu_inference");
  expect(h.changed).not.toHaveBeenCalled();
});
