import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { activityPeriods, countWords } from "../src/core/activity";
import { ActivityStore } from "../src/main/activity";

const directories: string[] = [];
afterEach(async () => {
  await Promise.all(directories.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "textify-activity-"));
  directories.push(directory);
  return join(directory, "activity.json");
}

describe("private activity totals", () => {
  it("counts words in space-delimited and Chinese dictation", () => {
    expect(countWords("Hello, world!")).toBe(2);
    expect(countWords("你好世界")).toBeGreaterThan(0);
    expect(countWords("  ")).toBe(0);
  });

  it("groups stored days into Monday-based weeks and calendar months across a year boundary", () => {
    const days = [
      { date: "2025-12-31", words: 2, dictations: 1, recordingSeconds: 8, estimatedTimeSavedSeconds: 3 },
      { date: "2026-01-01", words: 3, dictations: 1, recordingSeconds: 9, estimatedTimeSavedSeconds: 4 },
      { date: "2026-01-05", words: 5, dictations: 2, recordingSeconds: 12, estimatedTimeSavedSeconds: 6 },
    ];
    const today = new Date(2026, 0, 6, 12);
    const daily = activityPeriods(days, "day", today);
    expect(daily).toHaveLength(30);
    expect(daily.at(-1)?.key).toBe("2026-01-06");
    expect(daily.find((period) => period.key === "2026-01-01")?.totals.words).toBe(3);

    const weekly = activityPeriods(days, "week", today);
    expect(weekly).toHaveLength(8);
    expect(weekly.find((period) => period.key === "2025-12-29")?.totals).toEqual({
      words: 5, dictations: 2, recordingSeconds: 17, estimatedTimeSavedSeconds: 7,
    });
    expect(weekly.at(-1)?.key).toBe("2026-01-05");
    expect(weekly.at(-1)?.totals.words).toBe(5);

    const monthly = activityPeriods(days, "month", today);
    expect(monthly).toHaveLength(6);
    expect(monthly.find((period) => period.key === "2025-12-01")?.totals.words).toBe(2);
    expect(monthly.at(-1)?.key).toBe("2026-01-01");
    expect(monthly.at(-1)?.totals.words).toBe(8);
  });

  it("persists only daily numbers and calculates a bounded time estimate", async () => {
    const path = await fixture();
    const activity = new ActivityStore(path);
    await activity.load();
    await activity.record(
      { words: 20, recordingSeconds: 12, elapsedSeconds: 15 },
      new Date(2026, 8, 23, 11),
    );
    await activity.record(
      { words: 1, recordingSeconds: 8, elapsedSeconds: 10 },
      new Date(2026, 8, 24, 11),
    );
    expect(activity.snapshot().totals).toEqual({
      words: 21,
      dictations: 2,
      recordingSeconds: 20,
      estimatedTimeSavedSeconds: 15,
    });
    const saved = await readFile(path, "utf8");
    expect(saved).not.toContain("transcript");
    expect(saved).not.toContain("audio");
    expect(JSON.parse(saved).days.map((day: { date: string }) => day.date)).toEqual([
      "2026-09-23", "2026-09-24",
    ]);
    const restored = new ActivityStore(path);
    await restored.load();
    expect(restored.snapshot()).toEqual(activity.snapshot());
    expect(restored.snapshot().days[1].estimatedTimeSavedSeconds).toBe(0);
  });

  it("leaves unreadable activity data untouched", async () => {
    const path = await fixture();
    const saved = '{"version":1,"days":[{"date":"2026-09-23","words":"invalid"}]}';
    await writeFile(path, saved);
    const activity = new ActivityStore(path);
    await expect(activity.load()).rejects.toThrow("activity_invalid");
    expect(await readFile(path, "utf8")).toBe(saved);
  });
});
