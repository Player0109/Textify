import { describe, expect, it } from "vitest";
import { processText } from "../src/core/text";
import { SpeechGuard, stitch, trimSilence, windows } from "../src/core/audio";
import { validatePreferences } from "../src/main/preferences";
describe("ported text rules", () => {
  it.each([
    [
      "hello comma this is textify period new paragraph i am testing",
      "Hello, this is textify.\n\nI am testing",
    ],
    ["send to name at sign example period com", "Send to name@example. Com"],
    ["um hello comma uh you know world period", "Hello, world."],
    ["hello comma, world period.", "Hello, world."],
    ["open quote hello close quote new line next", '"Hello"\nNext'],
    [
      "word hyphen word forward slash path backslash file",
      "Word-word/path\\file",
    ],
  ])("%s", (raw, expected) => expect(processText(raw)).toBe(expected));
  it("protects replacements, including command words and capitalization", () => {
    expect(
      processText("brand new paragraph textify period", [
        { trigger: "brand", replacement: "iPhone new line" },
        { trigger: "textify", replacement: "textify" },
      ]),
    ).toBe("iPhone new line\n\ntextify.");
  });
  it("matches whole phrases longest first without interpreting replacement output", () => {
    expect(
      processText("new york and yorkshire", [
        { trigger: "york", replacement: "Y" },
        { trigger: "new york", replacement: "NYC" },
      ]),
    ).toBe("NYC and yorkshire");
  });
});
describe("audio rules", () => {
  it("ignores a click and detects sustained speech after startup grace", () => {
    const guard = new SpeechGuard();
    for (let i = 0; i < 4; i++) guard.accept(new Float32Array(320));
    guard.accept(new Float32Array(320).fill(0.5));
    guard.accept(new Float32Array(320));
    expect(guard.detected).toBe(false);
    for (let i = 0; i < 6; i++) guard.accept(new Float32Array(320).fill(0.1));
    expect(guard.detected).toBe(true);
  });
  it("removes silence but preserves internal pauses", () => {
    expect(trimSilence(new Float32Array(16000))).toHaveLength(0);
    const sample = new Float32Array(32000);
    sample.fill(0.1, 8000, 12000);
    sample.fill(0.1, 20000, 24000);
    const trimmed = trimSilence(sample);
    expect(trimmed.length).toBeGreaterThan(20000);
    expect(trimmed.some((x) => x === 0)).toBe(true);
  });
  it("bounds every window and retains forced-boundary overlap", () => {
    const audio = new Float32Array(16000 * 300).fill(0.1),
      chunks = windows(audio);
    expect(chunks.every((chunk) => chunk.length <= 29.5 * 16000)).toBe(true);
    expect(
      chunks.reduce((n, chunk) => n + chunk.length, 0) -
        (chunks.length - 1) * 6400,
    ).toBe(audio.length);
    expect(stitch("hello there friend", "there friend again")).toBe(
      "hello there friend again",
    );
    expect(stitch("very", "very good")).toBe("very very good");
  });
});
describe("preferences validation", () => {
  const value = {
    microphone: "default",
    trigger: "right-control",
    replacements: [],
  };
  it("rejects unexpected fields, invalid triggers and duplicate vocabulary", () => {
    expect(() =>
      validatePreferences({ ...value, shellCommand: "anything" }),
    ).toThrow();
    expect(() =>
      validatePreferences({ ...value, trigger: "right-command" }, "linux"),
    ).toThrow();
    expect(() =>
      validatePreferences({
        ...value,
        replacements: [
          { trigger: "abc", replacement: "A" },
          { trigger: "ABC", replacement: "B" },
        ],
      }),
    ).toThrow();
  });
});
