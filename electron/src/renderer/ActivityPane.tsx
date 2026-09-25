import { useEffect, useState } from "react";
import { activityPeriods, type ActivityGrouping } from "../core/activity";
import type { ActivitySnapshot, Phase } from "../shared";

const number = new Intl.NumberFormat();

function duration(seconds: number): string {
  const whole = Math.round(seconds);
  if (whole < 60) return `${whole} sec`;
  if (whole < 3600) return `${Math.floor(whole / 60)} min`;
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  return minutes ? `${hours} hr ${minutes} min` : `${hours} hr`;
}

export function ActivityPane({ phase }: { phase: Phase }) {
  const [activity, setActivity] = useState<ActivitySnapshot>();
  const [grouping, setGrouping] = useState<ActivityGrouping>("month");
  const [selectedKey, setSelectedKey] = useState<string>();
  const [error, setError] = useState(false);

  useEffect(() => {
    let active = true;
    void window.textify.activity().then(
      (result) => {
        if (active) {
          setActivity(result);
          setError(false);
        }
      },
      () => { if (active) setError(true); },
    );
    return () => { active = false; };
  }, [phase]);

  if (error && !activity)
    return (
      <section className="activity-unavailable">
        <h2>Activity data could not be read.</h2>
        <p>Your saved activity has not been changed.</p>
      </section>
    );
  if (!activity) return <p className="activity-loading">Loading activity…</p>;

  const periods = activityPeriods(activity.days, grouping);
  const peak = Math.max(0, ...periods.map((period) => period.totals.words));
  const activeKey = selectedKey ?? periods[periods.length - 1].key;
  const activePeriod = periods.find((period) => period.key === activeKey);
  const totals = activeKey === "all" ? activity.totals : activePeriod?.totals ?? activity.totals;
  const periodName = activeKey === "all" ? "All time" : activePeriod?.fullLabel ?? "Current period";
  const chartName = grouping === "day" ? "Daily activity" : grouping === "week" ? "Weekly activity" : "Monthly activity";
  const chartRange = grouping === "day" ? "Last 30 days" : grouping === "week" ? "Last 8 weeks" : "Last 6 months";
  return (
    <div className="activity-page">
      <div className="activity-toolbar">
        <div className="activity-grouping" role="group" aria-label="Group activity by">
          {(["day", "week", "month"] as const).map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={grouping === value}
              onClick={() => { setGrouping(value); setSelectedKey(undefined); }}
            >{value[0].toUpperCase() + value.slice(1)}</button>
          ))}
        </div>
        <span>From completed dictations</span>
      </div>

      <div className="activity-dashboard">
        <section className="activity-chart-panel" aria-labelledby="activity-chart-title">
          <div className="activity-chart-heading">
            <div>
              <h2 id="activity-chart-title">{chartName}</h2>
              <p>Words dictated · {chartRange.toLowerCase()}</p>
            </div>
            {peak > 0 && <span>Peak: {number.format(peak)} words</span>}
          </div>
          {peak ? (
            <div className="activity-plot">
              <div className="activity-scale" aria-hidden="true">
                <span>{number.format(peak)}</span>
                <span>{number.format(Math.round(peak / 2))}</span>
                <span>0</span>
              </div>
              <div className={`activity-chart group-${grouping}`} role="group" aria-label={`${chartName}, words dictated`}>
                {periods.map((period, index) => (
                  <button
                    className="activity-period"
                    key={period.key}
                    type="button"
                    aria-pressed={activeKey === period.key}
                    aria-label={`${period.fullLabel}: ${number.format(period.totals.words)} words`}
                    title={`${period.fullLabel}: ${number.format(period.totals.words)} words`}
                    onClick={() => setSelectedKey(period.key)}
                  >
                    <span className="activity-bar-track" aria-hidden="true">
                      <span className={period.totals.words ? "activity-bar has-words" : "activity-bar"} style={{ height: `${period.totals.words / peak * 100}%` }} />
                    </span>
                    <span className="activity-period-label" aria-hidden="true">
                      {grouping !== "day" || index % 7 === 1 || index === periods.length - 1 ? period.label : ""}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="activity-chart-empty">
              {activity.totals.dictations === 0
                ? "Your first completed dictation will appear here."
                : `No words dictated in the ${chartRange.toLowerCase()}.`}
            </div>
          )}
        </section>

        <section className="activity-summary" aria-label={`Activity totals for ${periodName}`}>
          <div className="activity-summary-heading">
            <span>Selected period</span>
            <h2>{periodName}</h2>
          </div>
          <div className="activity-summary-primary">
            <span>Words dictated</span>
            <strong>{number.format(totals.words)}</strong>
          </div>
          <div className="activity-summary-rows">
            <div><span>Dictations</span><strong>{number.format(totals.dictations)}</strong></div>
            <div><span>Recording time</span><strong>{duration(totals.recordingSeconds)}</strong></div>
            <div><span>Estimated time saved</span><strong>{duration(totals.estimatedTimeSavedSeconds)}</strong></div>
          </div>
          {activeKey !== "all" && <button className="text-button activity-all-time" onClick={() => setSelectedKey("all")}>View all time</button>}
        </section>
      </div>

      <div className="activity-footer">
        <div>
          <strong>Your data stays on this device</strong>
          <p>Textify keeps one numeric summary for each day you dictate. It does not save audio, transcripts, or destination apps.</p>
          <p>Time saved estimates typing at 40 words per minute minus the time to produce the text; edits are not measured.</p>
        </div>
        {error && <p role="alert">Activity could not be refreshed.</p>}
      </div>
    </div>
  );
}
