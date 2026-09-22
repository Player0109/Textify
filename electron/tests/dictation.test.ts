import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Dictation, type DictationPorts } from "../src/core/dictation";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
function harness(overrides: Partial<DictationPorts> = {}) {
  let samples: (data: Float32Array) => void = () => {};
  const ports = {
    target: vi.fn(async () => ({ target: "42", secure: false })),
    start: vi.fn(
      async (_id: number, callback: (data: Float32Array) => void) => {
        samples = callback;
      },
    ),
    stop: vi.fn(async () => {}),
    transcribe: vi.fn(async () => "hello comma world"),
    insert: vi.fn(async () => "sent" as const),
    changed: vi.fn(),
    ...overrides,
  };
  const app = new Dictation(ports, () => []);
  const speech = (frames = 20) => {
    for (let i = 0; i < frames; i++) samples(new Float32Array(320).fill(0.1));
  };
  return { app, ports, speech, samples: (data: Float32Array) => samples(data) };
}
describe("dictation lifecycle", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  it("keeps Copy available after clipboard failure and waits for a successful write", async () => {
    const h = harness();
    h.app.press(true);
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    await expect(
      h.app.copy(async () => {
        throw new Error("clipboard unavailable");
      }),
    ).rejects.toThrow();
    expect(h.app.pending).toBe("Hello, world");
    expect(h.app.phase).toBe("copy");
    const write = deferred<void>();
    const copying = h.app.copy(() => write.promise);
    h.app.press();
    h.app.dismiss();
    const duplicate = vi.fn(async () => {});
    await h.app.copy(duplicate);
    expect(duplicate).not.toHaveBeenCalled();
    expect(h.ports.start).toHaveBeenCalledOnce();
    expect(h.app.pending).toBe("Hello, world");
    write.resolve();
    await copying;
    expect(h.app.phase).toBe("idle");
    expect(h.app.pending).toBe("");
    expect(h.app.busy).toBe(false);
  });
  it("records immediately but discards an accidental tap", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(100);
    expect(h.ports.start).toHaveBeenCalledOnce();
    await h.app.release();
    expect(h.app.phase).toBe("idle");
    expect(h.ports.transcribe).not.toHaveBeenCalled();
    expect(h.ports.stop).toHaveBeenCalledWith(1, true);
  });
  it("transcribes and inserts exactly once after an accepted hold", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await Promise.all([h.app.release(), h.app.release()]);
    expect(h.ports.insert).toHaveBeenCalledExactlyOnceWith("Hello, world", {
      target: "42",
      secure: false,
    });
    expect(h.app.phase).toBe("idle");
    expect(h.app.pending).toBe("");
  });
  it("does not start the microphone after release during target admission", async () => {
    const target = deferred<{ target: string; secure: boolean }>();
    const h = harness({ target: () => target.promise });
    h.app.press();
    const releasing = h.app.release();
    target.resolve({ target: "42", secure: false });
    await releasing;
    expect(h.ports.start).not.toHaveBeenCalled();
    expect(h.ports.insert).not.toHaveBeenCalled();
  });
  it("drains delayed microphone startup before accepting another hold", async () => {
    const start = deferred<void>();
    const h = harness({ start: vi.fn(() => start.promise) });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    const release = h.app.release();
    h.app.press();
    expect(h.ports.start).toHaveBeenCalledOnce();
    start.resolve();
    await release;
    expect(h.app.phase).toBe("idle");
    expect(h.ports.transcribe).not.toHaveBeenCalled();
  });
  it("cancels normal shortcut use before speech", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.app.otherKey();
    await vi.advanceTimersByTimeAsync(1);
    h.speech();
    await h.app.release();
    expect(h.ports.transcribe).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
  });
  it("does not cancel extra keys after sustained speech", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    h.app.otherKey();
    await h.app.release();
    expect(h.ports.insert).toHaveBeenCalledOnce();
  });
  it("discards silence and cancelled samples without inference", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.samples(new Float32Array(320));
    await h.app.release();
    expect(h.ports.transcribe).not.toHaveBeenCalled();
    expect(h.app.message).toMatch(/No speech detected/);
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.cancel();
    h.speech();
    await h.app.release();
    expect(h.ports.insert).not.toHaveBeenCalled();
  });
  it("reports an accepted hold that received no audio frames", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    await h.app.release();
    expect(h.app.phase).toBe("error");
    expect(h.app.message).toMatch(/No microphone audio/);
    expect(h.ports.transcribe).not.toHaveBeenCalled();
  });
  it("does not record in a positively detected password field", async () => {
    const h = harness({ target: async () => ({ target: "42", secure: true }) });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    expect(h.ports.start).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
  });
  it("keeps manual results only until dismissed or the next hold", async () => {
    const h = harness();
    h.app.press(true);
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.target).not.toHaveBeenCalled();
    expect(h.ports.insert).not.toHaveBeenCalled();
    expect(h.app.pending).toBe("Hello, world");
    h.app.dismiss();
    expect(h.app.pending).toBe("");
    expect(h.app.phase).toBe("idle");
  });
  it("does not offer a retry after a changed target", async () => {
    const h = harness({ insert: async () => "skipped" });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.app.pending).toBe("");
    expect(h.app.phase).toBe("error");
    expect(h.app.message).toMatch(/could not confirm/);
  });
  it("offers explicit Copy when insertion is unavailable before paste", async () => {
    const h = harness({ insert: async () => "unavailable" });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.app.phase).toBe("copy");
    expect(h.app.pending).toBe("Hello, world");
  });
  it("aborts the whole result when recognition rejects a window", async () => {
    const h = harness({ transcribe: async () => null });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.insert).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("error");
    expect(h.app.message).toMatch(/could not recognize/);
  });
  it("waits for cancelled recognition and ignores late results", async () => {
    const recognition = deferred<string>();
    const h = harness({ transcribe: () => recognition.promise });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    const release = h.app.release();
    await vi.advanceTimersByTimeAsync(1);
    const cancel = h.app.cancel();
    h.app.press();
    expect(h.ports.start).toHaveBeenCalledOnce();
    recognition.resolve("stale result");
    await Promise.all([release, cancel]);
    expect(h.ports.insert).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
  });
  it("processes at the five-minute cap without inserting twice on release", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await vi.advanceTimersByTimeAsync(300000);
    await h.app.release();
    expect(h.ports.insert).toHaveBeenCalledOnce();
  });
});
