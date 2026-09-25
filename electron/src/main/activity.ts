import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { ActivityDay, ActivitySnapshot, ActivityTotals } from "../shared";

type CompletedDictation = {
  words: number;
  recordingSeconds: number;
  elapsedSeconds: number;
};

const zero = (): ActivityTotals => ({
  words: 0,
  dictations: 0,
  recordingSeconds: 0,
  estimatedTimeSavedSeconds: 0,
});

function dayKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function validDay(value: unknown): value is ActivityDay {
  if (!value || typeof value !== "object") return false;
  const day = value as ActivityDay;
  return (
    /^\d{4}-\d{2}-\d{2}$/.test(day.date) &&
    Number.isSafeInteger(day.words) && day.words >= 0 &&
    Number.isSafeInteger(day.dictations) && day.dictations >= 0 &&
    Number.isFinite(day.recordingSeconds) && day.recordingSeconds >= 0 &&
    Number.isFinite(day.estimatedTimeSavedSeconds) && day.estimatedTimeSavedSeconds >= 0
  );
}

export class ActivityStore {
  private days: ActivityDay[] = [];
  private pending: Promise<void> = Promise.resolve();

  constructor(private path: string) {}

  async load(): Promise<void> {
    let raw: string;
    try {
      raw = await readFile(this.path, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
      throw error;
    }
    const saved: unknown = JSON.parse(raw);
    if (
      !saved || typeof saved !== "object" ||
      (saved as { version?: unknown }).version !== 1 ||
      !Array.isArray((saved as { days?: unknown }).days) ||
      !(saved as { days: unknown[] }).days.every(validDay)
    ) throw new Error("activity_invalid");
    this.days = (saved as { days: ActivityDay[] }).days.map((day) => ({
      date: day.date,
      words: day.words,
      dictations: day.dictations,
      recordingSeconds: day.recordingSeconds,
      estimatedTimeSavedSeconds: day.estimatedTimeSavedSeconds,
    }));
  }

  snapshot(): ActivitySnapshot {
    const totals = zero();
    const days = this.days.map((day) => ({ ...day }));
    for (const day of days) {
      totals.words += day.words;
      totals.dictations += day.dictations;
      totals.recordingSeconds += day.recordingSeconds;
      totals.estimatedTimeSavedSeconds += day.estimatedTimeSavedSeconds;
    }
    return { totals, days };
  }

  record(result: CompletedDictation, date = new Date()): Promise<void> {
    if (
      !Number.isSafeInteger(result.words) || result.words < 0 ||
      !Number.isFinite(result.recordingSeconds) || result.recordingSeconds <= 0 ||
      !Number.isFinite(result.elapsedSeconds) || result.elapsedSeconds < 0
    ) return Promise.resolve();
    const key = dayKey(date);
    let day = this.days.find((entry) => entry.date === key);
    if (!day) {
      day = { date: key, ...zero() };
      this.days.push(day);
      this.days.sort((a, b) => a.date.localeCompare(b.date));
    }
    day.words += result.words;
    day.dictations++;
    day.recordingSeconds += result.recordingSeconds;
    // 40 WPM is an illustrative typing baseline; this cannot measure editing time.
    day.estimatedTimeSavedSeconds += Math.max(
      0,
      result.words * 60 / 40 - result.elapsedSeconds,
    );
    return this.save();
  }

  flush(): Promise<void> {
    return this.pending;
  }

  private save(): Promise<void> {
    const contents = JSON.stringify({ version: 1, days: this.days });
    const task = this.pending.catch(() => {}).then(async () => {
      await mkdir(dirname(this.path), { recursive: true });
      await writeFile(`${this.path}.tmp`, contents);
      await rename(`${this.path}.tmp`, this.path);
    });
    this.pending = task;
    return task;
  }
}
