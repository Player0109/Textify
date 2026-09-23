import type { Preferences } from "../shared";
import { LANGUAGES as languages } from "../shared";
export function defaults(
  platform = process.platform,
  wayland = false,
): Preferences {
  return {
    microphone: "default",
    trigger:
      platform === "darwin"
        ? "right-command"
        : wayland
          ? "control-space"
          : "right-control",
    replacements: [],
    customWords: [],
    language: "en",
    activeModelID: "ggml-small.en-q5_1",
    launchAtLogin: false,
    exclusions: [],
    overlay: { x: 0, y: 0, scale: 1 },
  };
}
export function validatePreferences(
  value: unknown,
  platform = process.platform,
): Preferences {
  const input = value as Preferences;
  if (
    !input ||
    typeof input !== "object" ||
    Object.keys(input).some((key) => !Object.keys(defaults()).includes(key))
  )
    throw new Error("preferences_invalid");
  // Upgrade the earlier Electron preview without dropping existing choices.
  const next = { ...defaults(platform), ...input };
  if (
    typeof next.microphone !== "string" ||
    next.microphone.length > 512 ||
    ![
      "right-command",
      "right-option",
      "right-control",
      "control-space",
    ].includes(next.trigger) ||
    (platform !== "darwin" &&
      ["right-command", "right-option"].includes(next.trigger)) ||
    !Array.isArray(next.replacements) ||
    next.replacements.length > 200 ||
    !languages[next.language] ||
    typeof next.activeModelID !== "string" ||
    !/^[a-zA-Z0-9._-]{1,240}$/.test(next.activeModelID) ||
    typeof next.launchAtLogin !== "boolean"
  )
    throw new Error("preferences_invalid");
  const seen = new Set<string>();
  for (const pair of next.replacements) {
    if (
      !pair ||
      typeof pair.trigger !== "string" ||
      typeof pair.replacement !== "string" ||
      !pair.trigger.trim() ||
      !pair.replacement.trim() ||
      pair.trigger.length > 200 ||
      pair.replacement.length > 1000 ||
      seen.has(pair.trigger.trim().toLowerCase())
    )
      throw new Error("replacement_invalid");
    seen.add(pair.trigger.trim().toLowerCase());
  }
  if (
    !Array.isArray(next.customWords) ||
    next.customWords.length > 100 ||
    next.customWords.some(
      (word) =>
        typeof word !== "string" ||
        !word.trim() ||
        word.length > 80 ||
        /[\r\n\0]/.test(word),
    ) ||
    next.customWords.join(", ").length > 2000 ||
    new Set(next.customWords.map((word) => word.trim().toLowerCase())).size !==
      next.customWords.length
  )
    throw new Error("custom_words_invalid");
  if (
    !Array.isArray(next.exclusions) ||
    next.exclusions.length > 200 ||
    next.exclusions.some(
      (entry) =>
        !entry ||
        typeof entry.id !== "string" ||
        !entry.id ||
        entry.id.length > 4096 ||
        /[\r\n\0]/.test(entry.id) ||
        typeof entry.name !== "string" ||
        !entry.name ||
        entry.name.length > 256,
    ) ||
    new Set(next.exclusions.map((entry) => entry.id)).size !==
      next.exclusions.length
  )
    throw new Error("exclusions_invalid");
  if (
    !next.overlay ||
    !Number.isFinite(next.overlay.x) ||
    !Number.isFinite(next.overlay.y) ||
    !Number.isFinite(next.overlay.scale) ||
    Math.abs(next.overlay.x) > 2000 ||
    Math.abs(next.overlay.y) > 2000 ||
    next.overlay.scale < 0.5 ||
    next.overlay.scale > 2
  )
    throw new Error("overlay_invalid");
  return {
    ...next,
    replacements: next.replacements.map((pair) => ({
      trigger: pair.trigger.trim(),
      replacement: pair.replacement,
    })),
    customWords: next.customWords.map((word) => word.trim()),
    exclusions: next.exclusions.map((entry) => ({
      id: entry.id,
      name: entry.name,
    })),
    overlay: {
      x: next.overlay.x,
      y: next.overlay.y,
      scale: next.overlay.scale,
    },
  };
}
