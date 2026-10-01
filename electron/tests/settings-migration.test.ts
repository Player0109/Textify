import { describe, expect, it } from "vitest";
import { defaults, validatePreferences } from "../src/main/preferences";
import { processText } from "../src/core/text";
import { desktopEntry } from "../src/main/startup";
describe("settings and language migration", () => {
  it("upgrades the first Electron preferences without dropping vocabulary", () => {
    const next = validatePreferences({
      trigger: "right-control",
      microphone: "device",
      replacements: [{ trigger: "abc", replacement: "ABC" }],
    });
    expect(next.replacements).toHaveLength(1);
    expect(next.microphone).toBe("device");
    expect(next.language).toBe("en");
    expect(next.saveRecordings).toBe(false);
  });
  it("accepts only a boolean training recordings choice", () => {
    expect(validatePreferences({ ...defaults(), saveRecordings: true }).saveRecordings).toBe(true);
    expect(() =>
      validatePreferences({ ...defaults(), saveRecordings: "yes" }),
    ).toThrow();
  });
  it("turns on update checks for earlier settings and rejects invalid values", () => {
    const earlier: Record<string, unknown> = { ...defaults() };
    delete earlier.checkForUpdates;
    expect(validatePreferences(earlier).checkForUpdates).toBe(true);
    expect(
      validatePreferences({ ...defaults(), checkForUpdates: false })
        .checkForUpdates,
    ).toBe(false);
    expect(() =>
      validatePreferences({ ...defaults(), checkForUpdates: "yes" }),
    ).toThrow();
  });
  it("raises quiet speech unless the saved choice turned it off", () => {
    expect(
      validatePreferences({ trigger: "right-control", replacements: [] })
        .raiseQuietSpeech,
    ).toBe(true);
    expect(
      validatePreferences({ ...defaults(), raiseQuietSpeech: false })
        .raiseQuietSpeech,
    ).toBe(false);
    expect(() =>
      validatePreferences({ ...defaults(), raiseQuietSpeech: "yes" }),
    ).toThrow();
  });
  it("rejects duplicate custom words and invalid overlay sizes", () => {
    expect(() =>
      validatePreferences({
        ...defaults(),
        customWords: ["Textify", "textify"],
      }),
    ).toThrow();
    expect(() =>
      validatePreferences({
        ...defaults(),
        overlay: { x: 0, y: 0, scale: 20 },
      }),
    ).toThrow();
  });
  it("preserves Hindi and other language output without English commands or replacements", () => {
    const raw = "  यह comma शब्द है।  ";
    expect(
      processText(raw, [{ trigger: "comma", replacement: "," }], "hi"),
    ).toBe(raw.trim());
  });
  it("quotes Linux autostart paths and escapes field-code substitutions", () => {
    expect(desktopEntry("/home/user/Apps/Textify 100%.AppImage")).toContain(
      'Exec="/home/user/Apps/Textify 100%%.AppImage" --background',
    );
    expect(() => desktopEntry("/path\nExec=malicious")).toThrow();
  });
});
