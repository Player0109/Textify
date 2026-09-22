import React, { useState } from "react";
import type { Preferences, Snapshot } from "../shared";
export function Exclusions({
  state,
  busy,
  save,
}: {
  state: Snapshot;
  busy: boolean;
  save(value: Preferences): Promise<boolean>;
}) {
  const [apps, setApps] = useState<{ id: string; name: string }[]>([]),
    [selected, setSelected] = useState(""),
    [error, setError] = useState("");
  const refresh = async () => {
    try {
      const values = await window.textify.apps();
      setApps(values);
      setSelected(values[0]?.id ?? "");
      setError(values.length ? "" : "No running apps could be identified.");
    } catch {
      setError("Running apps could not be read. Check desktop permissions.");
    }
  };
  return (
    <section className="vocabulary exclusions">
      <h2>Excluded apps</h2>
      <p>
        {state.exclusionsAvailable
          ? "Global dictation will not record while an excluded app is active."
          : "This desktop does not expose the active app reliably. App exclusions are unavailable; use the microphone button and explicit Copy."}
      </p>
      {state.exclusionsAvailable && (
        <>
          <button
            className="secondary"
            disabled={busy}
            onClick={() => void refresh()}
          >
            Choose a running app
          </button>
          {apps.length > 0 && (
            <div className="model-actions">
              <select
                aria-label="Running app"
                value={selected}
                onChange={(event) => setSelected(event.target.value)}
              >
                {apps.map((app) => (
                  <option value={app.id} key={app.id}>
                    {app.name}
                  </option>
                ))}
              </select>
              <button
                disabled={
                  busy ||
                  state.preferences.exclusions.some(
                    (entry) => entry.id === selected,
                  )
                }
                onClick={() => {
                  const chosen = apps.find((app) => app.id === selected);
                  if (chosen)
                    void save({
                      ...state.preferences,
                      exclusions: [...state.preferences.exclusions, chosen],
                    });
                }}
              >
                Exclude app
              </button>
            </div>
          )}
        </>
      )}
      {error && <p role="status">{error}</p>}
      <ul>
        {state.preferences.exclusions.map((entry) => (
          <li key={entry.id}>
            <span>
              {entry.name}
              <small>{entry.id}</small>
            </span>
            <button
              className="text-button"
              disabled={busy}
              onClick={() =>
                void save({
                  ...state.preferences,
                  exclusions: state.preferences.exclusions.filter(
                    (app) => app.id !== entry.id,
                  ),
                })
              }
            >
              Remove exclusion
            </button>
          </li>
        ))}
      </ul>
      {!state.preferences.exclusions.length && <p>No excluded apps.</p>}
    </section>
  );
}
