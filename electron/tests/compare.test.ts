import { describe, expect, it, vi } from "vitest";
import { differences, disagreement, tokens } from "../src/core/compare";
import { Comparison, committee } from "../src/main/comparison";
import type { RecordingStore } from "../src/main/recordings";
import type { ModelView } from "../src/shared";

// Each comparison worker exits only when its exit is released.
const exits = vi.hoisted(() => [] as (() => void)[]);
vi.mock("../src/main/worker", () => ({
  WhisperWorker: class {
    ready = false;
    async load() {
      this.ready = true;
    }
    async transcribe() {
      return "ask not";
    }
    stop() {
      return new Promise<void>((resolve) => exits.push(resolve));
    }
  },
}));

const marked = (text: string, marks: boolean[]) =>
  tokens(text)
    .filter((_, i) => marks[i])
    .map((token) => token.text);

describe("transcript comparison", () => {
  it("ignores case, punctuation and curly apostrophes", () => {
    const result = differences(
      "Hello, world. Don’t stop!",
      "hello world don't stop",
    );
    expect(result.edits).toBe(0);
    expect(disagreement("Hello, world.", ["hello world"])).toBe(0);
  });

  it("marks substituted, missing and extra words on each side", () => {
    const heard = "I am mostly seeing Miss Hare's ordinary words";
    const other = "I am mostly seeing mishears of ordinary words";
    const result = differences(heard, other);
    expect(marked(heard, result.left)).toEqual(["Miss", "Hare's"]);
    expect(marked(other, result.right)).toEqual(["mishears", "of"]);
    expect(result.edits).toBe(2);
    expect(marked("ask what you can", differences("ask what you can", "ask you can").left)).toEqual(["what"]);
    expect(marked("ask you can", differences("ask what you can", "ask you can").right)).toEqual([]);
  });

  it("scores the mean word error rate against each other model", () => {
    const text = "one two three four";
    expect(disagreement(text, [])).toBeUndefined();
    expect(disagreement(text, ["one two three four", "one too three for"])).toBe(0.25);
    expect(disagreement("", ["something was said"])).toBe(3);
  });

  it("never marks punctuation-only tokens", () => {
    const result = differences("wait — what", "wait what");
    expect(result.left).toEqual([false, false, false]);
    expect(result.edits).toBe(0);
  });
});

const model = (id: string, bytes: number, status: ModelView["status"] = "installed", languages = ["en"]) =>
  ({ id, bytes, status, languages, engine: id.startsWith("whisper") ? "whisper_cpp" : "transcribe_cpp" }) as ModelView;

describe("comparison models", () => {
  const models = [
    model("whisper-large-v3-q5_0", 1_081_140_203),
    model("whisper-large-v3-turbo-q5_0", 574_041_195),
    model("whisper-large-v2-q5_0", 1_080_732_091, "not-installed"),
    model("parakeet-tdt-0.6b-v3-q8-0", 739_508_576),
    model("parakeet-tdt-0.6b-v3-f16", 1_255_869_856),
    model("qwen3-asr-0.6b-q8-0", 850_423_456),
    model("qwen3-asr-1.7b-bf16", 4_083_087_904),
    model("confucius4-r2t2-q8_0", 2_477_512_064),
  ];

  it("uses the largest installed model from each other family", () => {
    expect(committee(models, "qwen3-asr-1.7b-bf16", "en").map((m) => m.id)).toEqual([
      "whisper-large-v3-q5_0",
      "parakeet-tdt-0.6b-v3-f16",
    ]);
    expect(committee(models, "ggml-small.en-q5_1", "en").map((m) => m.id)).toEqual([
      "parakeet-tdt-0.6b-v3-f16",
      "qwen3-asr-1.7b-bf16",
    ]);
  });

  it("skips models that cannot transcribe the clip's language", () => {
    const hindi = [model("whisper-large-v3-q5_0", 1, "installed", ["en", "hi"]), model("parakeet-tdt-0.6b-v3-f16", 2)];
    expect(committee(hindi, "qwen3-asr-1.7b-bf16", "hi").map((m) => m.id)).toEqual(["whisper-large-v3-q5_0"]);
  });

  it("finishes stopping only after every worker has exited", async () => {
    vi.useFakeTimers();
    let compared!: () => void;
    const done = new Promise<void>((resolve) => (compared = resolve));
    const store = {
      list: async () => [
        { id: "clip", modelID: "parakeet-tdt-0.6b-v3-f16", language: "en", comparisons: {} },
      ],
      samples: async () => new Float32Array(16000),
      compare: async () => {},
    };
    const comparison = new Comparison(
      "textify-whisper",
      store as unknown as RecordingStore,
      () => [model("whisper-large-v3-q5_0", 1)],
      (id) => id,
      () => true,
      () => true,
      compared,
    );
    comparison.schedule();
    await done;
    let stopped = false;
    const stopping = comparison.stop().then(() => {
      stopped = true;
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(exits).toHaveLength(1);
    expect(stopped).toBe(false);
    exits[0]();
    await stopping;
    expect(stopped).toBe(true);
    vi.useRealTimers();
  });
});
