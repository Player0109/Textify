export const SAMPLE_RATE = 16000;
export const MAX_SAMPLES = 300 * SAMPLE_RATE;
export function rms(samples: Float32Array): number {
  let sum = 0;
  for (const sample of samples) sum += sample * sample;
  return Math.sqrt(sum / Math.max(1, samples.length));
}
export class SpeechGuard {
  private frames = 0;
  private candidates = 0;
  private floor = -65;
  detected = false;
  accept(frame: Float32Array) {
    const db = 20 * Math.log10(Math.max(1e-8, rms(frame)));
    if (++this.frames <= 4 || this.detected) return;
    if (db > Math.max(this.floor + 12, -45)) this.candidates++;
    else {
      this.candidates = 0;
      this.floor = Math.min(-45, this.floor * 0.95 + db * 0.05);
    }
    this.detected = this.candidates >= 6;
  }
}
// Sorted levels (dBFS) of the complete 20 ms frames.
function frameLevels(samples: Float32Array): number[] {
  const levels: number[] = [];
  for (let start = 0; start + 320 <= samples.length; start += 320)
    levels.push(
      20 * Math.log10(Math.max(1e-8, rms(samples.subarray(start, start + 320)))),
    );
  return levels.sort((a, b) => a - b);
}
const percentile = (sorted: number[], p: number) =>
  sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
// A quiet recording, as when speaking farther from the microphone: its loudest
// frames (95th percentile) stay below -26 dBFS.
const quiet = (levels: number[]) =>
  levels.length > 0 && percentile(levels, 0.95) < -26;
export function trimSilence(samples: Float32Array): Float32Array {
  // Soft words in a quiet recording can fall below -45 dBFS, so the threshold
  // follows the room's noise floor there (10 dB above it, never below -60 dBFS)
  // and the margin grows from 150 ms to 400 ms.
  const levels = frameLevels(samples);
  const far = quiet(levels);
  const threshold = far
    ? Math.min(-45, Math.max(percentile(levels, 0.1) + 10, -60))
    : -45;
  const margin = far ? 6400 : 2400;
  let first = -1,
    last = 0,
    sustained = 0,
    longest = 0;
  for (let start = 0; start < samples.length; start += 320) {
    const loud =
      rms(samples.subarray(start, start + 320)) > 10 ** (threshold / 20);
    sustained = loud ? sustained + 1 : 0;
    longest = Math.max(longest, sustained);
    if (loud) {
      if (first < 0) first = start;
      last = start + 320;
    }
  }
  if (first < 0 || longest < 3) return new Float32Array();
  return samples.slice(
    Math.max(0, first - margin),
    Math.min(samples.length, last + margin),
  );
}
// Raises a quiet recording in place until its loudest frames reach -20 dBFS:
// at most +30 dB, and the peak stays below -1 dBFS. Other recordings are
// unchanged.
export function raiseQuiet(samples: Float32Array) {
  const levels = frameLevels(samples);
  if (!quiet(levels)) return;
  let peak = 0;
  for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
  const gain = Math.min(
    30,
    -20 - percentile(levels, 0.95),
    -1 - 20 * Math.log10(Math.max(1e-8, peak)),
  );
  if (gain <= 0) return;
  const factor = 10 ** (gain / 20);
  for (let i = 0; i < samples.length; i++) samples[i] *= factor;
}
export function windows(samples: Float32Array): Float32Array[] {
  if (samples.length <= 29.5 * SAMPLE_RATE) return [samples];
  const result: Float32Array[] = [];
  let start = 0;
  while (start < samples.length) {
    if (samples.length - start <= 29.5 * SAMPLE_RATE) {
      result.push(samples.subarray(start));
      break;
    }
    let end = start + 25 * SAMPLE_RATE,
      quiet = 0,
      split = -1;
    for (let i = end - 5 * SAMPLE_RATE; i < end; i += 320) {
      quiet =
        rms(samples.subarray(i, i + 320)) <= 10 ** (-45 / 20) ? quiet + 1 : 0;
      if (quiet >= 10) split = i + 320;
    }
    if (split > start) end = split;
    result.push(samples.subarray(start, end));
    start = split > start ? end : end - 6400;
  }
  return result;
}
export function stitch(previous: string, next: string): string {
  const a = previous.trim().split(/\s+/),
    b = next.trim().split(/\s+/);
  for (let n = Math.min(40, a.length, b.length); n >= 2; n--) {
    if (a.slice(-n).join(" ") === b.slice(0, n).join(" "))
      return `${previous.trim()} ${b.slice(n).join(" ")}`.trim();
  }
  return `${previous.trim()} ${next.trim()}`.trim();
}
