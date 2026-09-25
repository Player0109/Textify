import type { ActivityDay, ActivityTotals } from "../shared";

export function countWords(text: string): number {
  const segmenter = new Intl.Segmenter(undefined, { granularity: "word" });
  let words = 0;
  for (const segment of segmenter.segment(text))
    if (segment.isWordLike) words++;
  return words;
}

export type ActivityGrouping = "day" | "week" | "month";

export interface ActivityPeriod {
  key: string;
  label: string;
  fullLabel: string;
  totals: ActivityTotals;
}

function dateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function periodStart(date: Date, grouping: ActivityGrouping): Date {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12);
  if (grouping === "week") start.setDate(start.getDate() - (start.getDay() + 6) % 7);
  if (grouping === "month") start.setDate(1);
  return start;
}

export function activityPeriods(days: ActivityDay[], grouping: ActivityGrouping, today = new Date()): ActivityPeriod[] {
  const count = grouping === "day" ? 30 : grouping === "week" ? 8 : 6;
  const current = periodStart(today, grouping);
  const shortLabel = new Intl.DateTimeFormat(undefined, grouping === "month"
    ? { month: "short" } : { month: "short", day: "numeric" });
  const fullLabel = new Intl.DateTimeFormat(undefined, grouping === "month"
    ? { month: "long", year: "numeric" } : grouping === "day"
      ? { dateStyle: "long" } : { month: "short", day: "numeric", year: "numeric" });
  const periods = Array.from({ length: count }, (_, index) => {
    const start = new Date(current);
    if (grouping === "month") start.setMonth(start.getMonth() - (count - 1 - index));
    else start.setDate(start.getDate() - (count - 1 - index) * (grouping === "week" ? 7 : 1));
    const label = shortLabel.format(start);
    const end = new Date(start);
    if (grouping === "week") end.setDate(end.getDate() + 6);
    return {
      key: dateKey(start),
      label,
      fullLabel: grouping === "week" ? `${label}–${fullLabel.format(end)}` : fullLabel.format(start),
      totals: { words: 0, dictations: 0, recordingSeconds: 0, estimatedTimeSavedSeconds: 0 },
    };
  });
  const byKey = new Map(periods.map((period) => [period.key, period]));
  for (const day of days) {
    const [year, month, date] = day.date.split("-").map(Number);
    const period = byKey.get(dateKey(periodStart(new Date(year, month - 1, date, 12), grouping)));
    if (!period) continue;
    period.totals.words += day.words;
    period.totals.dictations += day.dictations;
    period.totals.recordingSeconds += day.recordingSeconds;
    period.totals.estimatedTimeSavedSeconds += day.estimatedTimeSavedSeconds;
  }
  return periods;
}
