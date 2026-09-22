import type { Preferences } from "../shared";
export function validatePreferences(
  value: unknown,
  platform = process.platform,
): Preferences {
  const input = value as Preferences;
  if (
    !input ||
    Object.keys(input).sort().join() !==
      ["microphone", "replacements", "trigger"].sort().join() ||
    typeof input.microphone !== "string" ||
    input.microphone.length > 512 ||
    !["right-command", "right-control", "control-space"].includes(
      input.trigger,
    ) ||
    (platform !== "darwin" && input.trigger === "right-command") ||
    !Array.isArray(input.replacements) ||
    input.replacements.length > 200
  )
    throw new Error("preferences_invalid");
  const seen = new Set<string>();
  for (const pair of input.replacements) {
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
  return {
    microphone: input.microphone,
    trigger: input.trigger,
    replacements: input.replacements.map((pair) => ({
      trigger: pair.trigger.trim(),
      replacement: pair.replacement,
    })),
  };
}
