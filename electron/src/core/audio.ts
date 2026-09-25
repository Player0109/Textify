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
export function trimSilence(samples: Float32Array): Float32Array {
  let first = -1,
    last = 0,
    sustained = 0,
    longest = 0;
  for (let start = 0; start < samples.length; start += 320) {
    const loud = rms(samples.subarray(start, start + 320)) > 10 ** (-45 / 20);
    sustained = loud ? sustained + 1 : 0;
    longest = Math.max(longest, sustained);
    if (loud) {
      if (first < 0) first = start;
      last = start + 320;
    }
  }
  if (first < 0 || longest < 3) return new Float32Array();
  return samples.slice(
    Math.max(0, first - 2400),
    Math.min(samples.length, last + 2400),
  );
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
