import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Dictation, type DictationPorts } from "../src/core/dictation";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
function harness(
  overrides: Partial<DictationPorts> = {},
  raiseQuietSpeech = () => true,
) {
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
  const app = new Dictation(
    ports,
    () => [],
    undefined,
    undefined,
    raiseQuietSpeech,
  );
  const speech = (frames = 20) => {
    for (let i = 0; i < frames; i++) samples(new Float32Array(320).fill(0.1));
  };
  return { app, ports, speech, samples: (data: Float32Array) => samples(data) };
}
describe("dictation lifecycle", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  it("keeps the destination icon with its session and clears it for manual dictation", async () => {
    const target = {
      target: "42",
      secure: false,
      appName: "TextEdit",
      appIcon: "data:image/png;base64,icon",
    };
    const h = harness({ target: async () => target });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    expect(h.app.application).toBe("TextEdit");
    expect(h.app.applicationIcon).toBe(target.appIcon);
    h.speech();
    await h.app.release();
    expect(h.ports.insert).toHaveBeenCalledWith("Hello, world", target);
    h.app.press(true);
    await vi.advanceTimersByTimeAsync(300);
    expect(h.app.application).toBe("Textify");
    expect(h.app.applicationIcon).toBe("");
    await h.app.cancel();
  });
  it("shows live text before release but inserts only the finalized transcript once", async () => {
    const stream = {
      beginStream: vi.fn(async () => {}),
      pushStream: vi.fn(async () => "live preview"),
      finishStream: vi.fn(async () => "stream final"),
      resetStream: vi.fn(async () => {}),
    };
    const h = harness({ streaming: () => stream });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await vi.advanceTimersByTimeAsync(1);
    expect(h.app.preview).toBe("live preview");
    expect(h.ports.insert).not.toHaveBeenCalled();
    await h.app.release();
    expect(h.ports.insert).toHaveBeenCalledExactlyOnceWith("Hello, world", {
      target: "42",
      secure: false,
    });
    expect(h.app.preview).toBe("");
    expect(stream.resetStream).toHaveBeenCalledOnce();
  });
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
  it("counts only delivered or successfully copied results", async () => {
    const completed = vi.fn();
    const h = harness({ completed });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(completed).toHaveBeenCalledExactlyOnceWith({
      words: 2,
      recordingSeconds: 0.4,
      elapsedSeconds: 0.3,
    });

    const manual = harness({ completed });
    manual.app.press(true);
    await vi.advanceTimersByTimeAsync(300);
    manual.speech();
    await manual.app.release();
    expect(completed).toHaveBeenCalledTimes(1);
    await expect(manual.app.copy(async () => { throw new Error("clipboard failed"); })).rejects.toThrow();
    expect(completed).toHaveBeenCalledTimes(1);
    await manual.app.copy(async () => {});
    expect(completed).toHaveBeenCalledTimes(2);

    const skipped = harness({ completed, insert: async () => "skipped" });
    skipped.app.press();
    await vi.advanceTimersByTimeAsync(300);
    skipped.speech();
    await skipped.app.release();
    expect(completed).toHaveBeenCalledTimes(2);

    const cancelled = harness({ completed });
    cancelled.app.press();
    await vi.advanceTimersByTimeAsync(300);
    cancelled.speech();
    await cancelled.app.cancel();
    expect(completed).toHaveBeenCalledTimes(2);
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
  it("silently discards silence and cancelled samples without inference", async () => {
    const h = harness();
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.samples(new Float32Array(320));
    await h.app.release();
    expect(h.ports.transcribe).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
    expect(h.app.message).toBe("");
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
  it("silently discards the whole result when recognition rejects a window", async () => {
    const h = harness({ transcribe: async () => null });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.insert).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
    expect(h.app.message).toBe("");
  });
  it("silently discards an empty recognition result", async () => {
    const h = harness({ transcribe: async () => "   " });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.insert).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
    expect(h.app.message).toBe("");
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
  it("skips recognition when the speech check finds under 0.25 s of speech", async () => {
    const h = harness({ speech: async () => 0.2 });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.transcribe).not.toHaveBeenCalled();
    expect(h.app.phase).toBe("idle");
    expect(h.app.message).toBe("");
  });
  it.each([
    ["finds speech", async () => 0.25],
    [
      "cannot run",
      async () => {
        throw new Error("speech_check");
      },
    ],
  ])("transcribes when the speech check %s", async (_, speech) => {
    const h = harness({ speech });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(h.ports.insert).toHaveBeenCalledOnce();
  });
  it.each([true, false])(
    "checks the whole recording raised; raising for recognition is %s",
    async (enabled) => {
      const checked: Float32Array[] = [];
      const heard: Float32Array[] = [];
      const recognized: Float32Array[] = [];
      const h = harness(
        {
          speech: async (samples) => {
            checked.push(samples);
            heard.push(samples.slice());
            return 1;
          },
          transcribe: async (samples) => {
            recognized.push(samples.slice());
            return "hello";
          },
        },
        () => enabled,
      );
      h.app.press();
      await vi.advanceTimersByTimeAsync(300);
      // Quiet speech at -40 dBFS between 0.8 s silences.
      for (let i = 0; i < 100; i++)
        h.samples(new Float32Array(320).fill(i >= 40 && i < 60 ? 0.01 : 0));
      await h.app.release();
      expect(heard[0]).toHaveLength(32000);
      expect(heard[0][16000]).toBeCloseTo(0.1, 6);
      expect(checked[0].every((x) => x === 0)).toBe(true);
      expect(recognized[0]).toHaveLength(19200);
      expect(recognized[0][9600]).toBeCloseTo(enabled ? 0.1 : 0.01, 6);
    },
  );
  it("ignores a speech check that finishes after cancellation", async () => {
    const check = deferred<number>();
    const h = harness({ speech: () => check.promise });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    const release = h.app.release();
    await vi.advanceTimersByTimeAsync(1);
    const cancel = h.app.cancel();
    check.resolve(1);
    await Promise.all([release, cancel]);
    expect(h.ports.transcribe).not.toHaveBeenCalled();
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
  it("offers the recognized audio with model and final text before delivery, then clears it", async () => {
    let saved: { audio: Float32Array; copy: Float32Array; modelText: string; finalText: string } | undefined;
    const h = harness({
      recorded: vi.fn((sample) => {
        saved = { ...sample, copy: sample.audio.slice() };
      }),
    });
    h.app.press();
    await vi.advanceTimersByTimeAsync(300);
    h.speech();
    await h.app.release();
    expect(saved?.modelText).toBe("hello comma world");
    expect(saved?.finalText).toBe("Hello, world");
    expect(saved?.copy.length).toBeGreaterThan(0);
    expect(saved?.copy.some((x) => x !== 0)).toBe(true);
    expect(saved?.audio.every((x) => x === 0)).toBe(true);
    expect(h.ports.insert).toHaveBeenCalledOnce();
  });
  it("does not offer cancelled or empty dictations for recording", async () => {
    const recognition = deferred<string>();
    const cancelled = harness({ transcribe: () => recognition.promise, recorded: vi.fn() });
    cancelled.app.press();
    await vi.advanceTimersByTimeAsync(300);
    cancelled.speech();
    const release = cancelled.app.release();
    await vi.advanceTimersByTimeAsync(1);
    const cancel = cancelled.app.cancel();
    recognition.resolve("late words");
    await Promise.all([release, cancel]);
    expect(cancelled.ports.recorded).not.toHaveBeenCalled();

    const empty = harness({ transcribe: async () => "  ", recorded: vi.fn() });
    empty.app.press();
    await vi.advanceTimersByTimeAsync(300);
    empty.speech();
    await empty.app.release();
    expect(empty.ports.recorded).not.toHaveBeenCalled();
  });
});
