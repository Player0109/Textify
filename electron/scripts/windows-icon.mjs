// Draws the Windows icon: the logo's T and waveform bars without the blue
// tile, on a transparent background. Every size is laid out on whole pixels
// so the taskbar, title bar and tray sizes stay sharp.
import { crc32, deflateSync } from "node:zlib";

// Measured from assets/textify-icon.png in its pixels: x from the T's centre
// line, y from the top of the T. The left bars mirror the right ones.
const logo = {
  armHalf: 286,
  arm: 129,
  stemHalf: 71.5,
  stem: 654,
  fillet: 40,
  gaps: [51.5, 35.5, 35.5],
  bars: [
    { width: 65.5, top: 274, bottom: 466 },
    { width: 77, top: 184, bottom: 534 },
    { width: 65.5, top: 274, bottom: 439 },
  ],
};
// The logo's blue and cyan, darkened enough to read on light and dark taskbars.
const colors = {
  t: [
    [0x2b, 0x80, 0xff],
    [0x10, 0x5c, 0xe8],
  ],
  bars: [
    [0x1c, 0xb8, 0xf2],
    [0x08, 0x8a, 0xdc],
  ],
};
// Win32 icon sizes for 100–200% display scaling.
export const sizes = [16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 128, 256];

function layout(size) {
  const margin = Math.max(1, size / 32);
  for (let scale = (size - 2 * margin) / 804; ; scale *= 0.98) {
    const px = (value) => Math.max(1, Math.round(value * scale));
    const stemHalf = px(logo.stemHalf);
    const bars = [];
    let x = stemHalf;
    for (const [index, bar] of logo.bars.entries()) {
      x += px(logo.gaps[index]);
      bars.push({ left: x, right: x + px(bar.width), top: px(bar.top), bottom: px(bar.bottom) });
      x += px(bar.width);
    }
    if (2 * x > size - 2 * margin) continue;
    const height = px(logo.stem);
    return {
      top: Math.floor((size - height) / 2),
      armHalf: px(logo.armHalf),
      arm: px(logo.arm),
      stemHalf,
      height,
      fillet: Math.round(logo.fillet * scale),
      bars,
    };
  }
}

// Point inside a rectangle whose corners are rounded by radius r.
function inRounded(x, y, left, top, right, bottom, r) {
  if (x < left || x > right || y < top || y > bottom) return false;
  const cx = Math.min(Math.max(x, left + r), right - r);
  const cy = Math.min(Math.max(y, top + r), bottom - r);
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

function shape(x, y, l) {
  const ax = Math.abs(x);
  if (inRounded(x, y, -l.armHalf, 0, l.armHalf, l.arm, l.arm / 2)) return "t";
  // The stem's top corners stay square so it joins the arm cleanly.
  if (ax <= l.stemHalf && y >= l.arm / 2 && y <= l.height) {
    if (y <= l.height - l.stemHalf) return "t";
    if (ax ** 2 + (y - (l.height - l.stemHalf)) ** 2 <= l.stemHalf ** 2) return "t";
  }
  // Concave fillets where the stem meets the arm.
  const f = l.fillet;
  if (f > 0 && ax >= l.stemHalf && ax <= l.stemHalf + f && y >= l.arm && y <= l.arm + f)
    if ((ax - l.stemHalf - f) ** 2 + (y - l.arm - f) ** 2 >= f * f) return "t";
  for (const bar of l.bars) {
    const r = (bar.right - bar.left) / 2;
    if (inRounded(ax, y, bar.left, bar.top, bar.right, bar.bottom, r)) return "bars";
  }
  return null;
}

const mix = ([a, b], t) => a.map((v, i) => v + (b[i] - v) * t);

// Straight-alpha RGBA pixels, sampled at least 256 times across the width.
export function draw(size) {
  const l = layout(size);
  const samples = Math.max(4, Math.ceil(256 / size));
  const rgba = Buffer.alloc(size * size * 4);
  const barTop = Math.min(...l.bars.map((bar) => bar.top));
  const barBottom = Math.max(...l.bars.map((bar) => bar.bottom));
  for (let py = 0; py < size; py++)
    for (let px = 0; px < size; px++) {
      let covered = 0;
      const sum = [0, 0, 0];
      for (let sy = 0; sy < samples; sy++)
        for (let sx = 0; sx < samples; sx++) {
          const x = px + (sx + 0.5) / samples - size / 2;
          const y = py + (sy + 0.5) / samples - l.top;
          const kind = shape(x, y, l);
          if (!kind) continue;
          const color =
            kind === "t"
              ? mix(colors.t, Math.min(1, Math.max(0, y / l.height)))
              : mix(colors.bars, Math.min(1, Math.max(0, (y - barTop) / (barBottom - barTop))));
          covered++;
          for (let i = 0; i < 3; i++) sum[i] += color[i];
        }
      if (!covered) continue;
      const offset = (py * size + px) * 4;
      for (let i = 0; i < 3; i++) rgba[offset + i] = Math.round(sum[i] / covered);
      rgba[offset + 3] = Math.round((255 * covered) / samples ** 2);
    }
  return rgba;
}

export function png(size, rgba) {
  const chunk = (type, data) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header.set([8, 6, 0, 0, 0], 8);
  const rows = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++)
    rgba.copy(rows, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// 32-bit bottom-up DIB with an AND mask, as Windows expects below 256 px.
function dib(size, rgba) {
  const maskRow = Math.ceil(size / 32) * 4;
  const out = Buffer.alloc(40 + size * size * 4 + maskRow * size);
  out.writeUInt32LE(40, 0);
  out.writeInt32LE(size, 4);
  out.writeInt32LE(size * 2, 8);
  out.writeUInt16LE(1, 12);
  out.writeUInt16LE(32, 14);
  out.writeUInt32LE(size * size * 4 + maskRow * size, 20);
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const from = (y * size + x) * 4;
      const to = 40 + ((size - 1 - y) * size + x) * 4;
      out.set([rgba[from + 2], rgba[from + 1], rgba[from], rgba[from + 3]], to);
      if (!rgba[from + 3])
        out[40 + size * size * 4 + (size - 1 - y) * maskRow + (x >> 3)] |= 0x80 >> (x & 7);
    }
  return out;
}

export function windowsIcon() {
  const images = sizes.map((size) => {
    const rgba = draw(size);
    return size === 256 ? png(size, rgba) : dib(size, rgba);
  });
  const header = Buffer.alloc(6 + 16 * sizes.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((size, index) => {
    const entry = 6 + 16 * index;
    header[entry] = size % 256;
    header[entry + 1] = size % 256;
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(images[index].length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += images[index].length;
  });
  return Buffer.concat([header, ...images]);
}
