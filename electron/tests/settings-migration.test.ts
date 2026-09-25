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
