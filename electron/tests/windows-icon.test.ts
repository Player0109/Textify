import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";

const { draw, sizes, windowsIcon } = await import(pathToFileURL(resolve("scripts/windows-icon.mjs")).href);

describe("Windows icon", () => {
  it("stores every Win32 size, as a bitmap below 256 px and a PNG at 256 px", () => {
    const ico: Buffer = windowsIcon();
    expect([ico.readUInt16LE(2), ico.readUInt16LE(4)]).toEqual([1, sizes.length]);
    sizes.forEach((size: number, index: number) => {
      const entry = 6 + 16 * index;
      expect(ico[entry] || 256).toBe(size);
      const image = ico.subarray(ico.readUInt32LE(entry + 12));
      if (size === 256) expect(image.subarray(1, 4).toString()).toBe("PNG");
      else
        expect([image.readUInt32LE(0), image.readInt32LE(4), image.readInt32LE(8), image.readUInt16LE(14)])
          .toEqual([40, size, size * 2, 32]);
    });
  });

  it.each(sizes as number[])("draws a symmetric mark on a transparent background at %i px", (size) => {
    const rgba: Buffer = draw(size);
    const alpha = (x: number, y: number) => rgba[(y * size + x) * 4 + 3];
    expect([alpha(0, 0), alpha(size - 1, 0), alpha(0, size - 1), alpha(size - 1, size - 1)]).toEqual([0, 0, 0, 0]);
    expect(alpha(size / 2, size / 2)).toBe(255);
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size / 2; x++) expect(alpha(x, y)).toBe(alpha(size - 1 - x, y));
  });
});
