import { describe, expect, it } from "vitest";
import { overlayBounds } from "../src/core/overlay-geometry";

describe("floating icon placement", () => {
  const area = { x: 0, y: 25, width: 1440, height: 875 };
  it("starts at bottom center, with positive X right and positive Y up", () => {
    const origin = overlayBounds(area, { x: 0, y: 0, scale: 1 }, false);
    const moved = overlayBounds(area, { x: 120, y: 70, scale: 1 }, false);
    expect(origin).toEqual({
      x: 548,
      y: 790,
      width: 344,
      height: 88,
      scale: 1,
    });
    expect(moved.x - origin.x).toBe(120);
    expect(moved.y - origin.y).toBe(-70);
  });
  it("preserves the bottom anchor when scaling or showing live text", () => {
    for (const scale of [0.5, 0.75, 1, 2]) {
      for (const expanded of [false, true]) {
        const frame = overlayBounds(area, { x: 0, y: 70, scale }, expanded);
        expect(frame.y + frame.height).toBe(area.y + area.height - 22 - 70);
        expect(frame.x + frame.width / 2).toBe(area.width / 2);
      }
    }
  });
  it("clamps each edge on a display with a negative origin", () => {
    const display = { x: -1600, y: -100, width: 1600, height: 900 };
    expect(
      overlayBounds(display, { x: -2000, y: 2000, scale: 2 }, true),
    ).toMatchObject({ x: -1600, y: -100 });
    expect(
      overlayBounds(display, { x: 2000, y: -2000, scale: 2 }, true),
    ).toMatchObject({ x: -688, y: 488 });
  });
  it("fits the complete expanded bar even on a very small work area", () => {
    const display = { x: 30, y: 40, width: 300, height: 120 };
    const frame = overlayBounds(display, { x: 2000, y: -2000, scale: 2 }, true);
    expect(frame.scale).toBeLessThan(1);
    expect(frame.x).toBeGreaterThanOrEqual(display.x);
    expect(frame.y).toBeGreaterThanOrEqual(display.y);
    expect(frame.x + frame.width).toBeLessThanOrEqual(
      display.x + display.width,
    );
    expect(frame.y + frame.height).toBeLessThanOrEqual(
      display.y + display.height,
    );
  });
});
