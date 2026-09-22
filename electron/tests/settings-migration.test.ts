import { describe, expect, it } from "vitest";
import {
  defaults,
  migrateNativeSettings,
  validatePreferences,
} from "../src/main/preferences";
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
  });
  it("copies supported native choices without enabling startup or reusing a CoreAudio device ID", () => {
    const current = defaults("darwin");
    const result = migrateNativeSettings(
      {
        trigger: "rightOption",
        transcriptionLanguage: "hi",
        activeModelID: "whisper-large-v3-turbo-q5_0",
        microphoneSelection: { deviceUID: "native-id" },
        launchAtLoginEnabled: true,
        excludedApps: [
          { bundleIdentifier: "com.example.app", displayName: "Example" },
        ],
      },
      current,
      "darwin",
    );
    expect(result.preferences).toMatchObject({
      trigger: "right-option",
      language: "hi",
      microphone: "default",
      launchAtLogin: false,
      exclusions: [{ id: "com.example.app", name: "Example" }],
    });
    expect(current.exclusions).toEqual([]);
  });
  it("explains unsupported native models and platform-specific preferences", () => {
    const result = migrateNativeSettings(
      {
        trigger: "rightCommand",
        activeModelID: "apple-only-runtime",
        excludedApps: [{ bundleIdentifier: "com.apple.TextEdit" }],
      },
      defaults("win32"),
      "win32",
    );
    expect(result.preferences.trigger).toBe("right-control");
    expect(result.preferences.exclusions).toEqual([]);
    expect(result.notes).toHaveLength(4);
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

it("imports a native model only when the running catalog admits its runtime", () => {
  const current = defaults("darwin");
  const raw = {
    activeModelID: "qwen3-asr-1.7b-bf16",
    transcriptionLanguage: "hi",
  };
  const result = migrateNativeSettings(raw, current, "darwin", [
    "qwen3-asr-1.7b-bf16",
  ]);
  expect(result.preferences.activeModelID).toBe(raw.activeModelID);
  expect(result.preferences.language).toBe("hi");
});
