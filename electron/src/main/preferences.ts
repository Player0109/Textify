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
export function migrateNativeSettings(
  raw: any,
  current: Preferences,
  platform = process.platform,
): { preferences: Preferences; notes: string[] } {
  if (
    !raw ||
    typeof raw !== "object" ||
    !["trigger", "transcriptionLanguage", "activeModelID", "excludedApps"].some(
      (key) => key in raw,
    )
  )
    throw new Error("native_settings_invalid");
  const trigger = (
    {
      rightCommand: "right-command",
      rightOption: "right-option",
      rightControl: "right-control",
      controlSpace: "control-space",
    } as const
  )[raw.trigger as string];
  const notes = [
    "Microphone selection and startup registration must be configured for this app.",
  ];
  const next = {
    ...current,
    launchAtLogin: current.launchAtLogin,
    microphone: "default",
  };
  if (
    trigger &&
    (platform === "darwin" ||
      !["right-command", "right-option"].includes(trigger))
  )
    next.trigger = trigger;
  else if (raw.trigger)
    notes.push(
      "The native trigger is unavailable on this platform; the current trigger was kept.",
    );
  if (languages[raw.transcriptionLanguage])
    next.language = raw.transcriptionLanguage;
  else if (raw.transcriptionLanguage)
    notes.push(
      "The saved language was not imported because it is unsupported.",
    );
  if (
    [
      "ggml-small.en-q5_1",
      "whisper-large-v2-q5_0",
      "whisper-large-v3-q5_0",
      "whisper-large-v3-turbo-q5_0",
    ].includes(raw.activeModelID)
  )
    next.activeModelID = raw.activeModelID;
  else if (raw.activeModelID)
    notes.push(
      "The native model uses a runtime that is not available in this preview.",
    );
  if (platform === "darwin" && Array.isArray(raw.excludedApps))
    next.exclusions = raw.excludedApps.map((entry: any) => ({
      id: entry.bundleIdentifier,
      name: entry.displayName,
    }));
  else if (raw.excludedApps?.length)
    notes.push(
      "macOS app exclusions were not imported on another operating system.",
    );
  if (raw.recordingOverlay)
    next.overlay = {
      x: raw.recordingOverlay.xOffset,
      y: raw.recordingOverlay.yOffset,
      scale: raw.recordingOverlay.scale,
    };
  return { preferences: validatePreferences(next, platform), notes };
}
