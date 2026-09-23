import type { Preferences } from "../shared";

type Rect = { x: number; y: number; width: number; height: number };

export function overlayBounds(
  area: Rect,
  preference: Preferences["overlay"],
  expanded: boolean,
) {
  const baseHeight = expanded ? 156 : 88;
  const scale = Math.min(
    preference.scale,
    area.width / 344,
    area.height / baseHeight,
  );
  const width = Math.round(344 * scale);
  const height = Math.round(baseHeight * scale);
  const clamp = (value: number, min: number, max: number) =>
    Math.min(max, Math.max(min, Math.round(value)));
  return {
    x: clamp(
      area.x + (area.width - width) / 2 + preference.x,
      area.x,
      area.x + area.width - width,
    ),
    // Electron's screen Y increases downward; native Textify's positive offset is up.
    y: clamp(
      area.y + area.height - height - 22 - preference.y,
      area.y,
      area.y + area.height - height,
    ),
    width,
    height,
    scale,
  };
}
