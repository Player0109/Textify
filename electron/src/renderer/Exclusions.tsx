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
    <section className="exclusions" aria-labelledby="exclusions-heading">
      <div className="exclusions-heading">
        <span className="exclusions-icon" aria-hidden="true">
          <svg
            width="23"
            height="23"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.6"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <rect x="3" y="4" width="18" height="16" rx="3" />
            <path d="M3 9h18M9 14.5h6" />
          </svg>
        </span>
        <div className="exclusions-copy">
          <h2 id="exclusions-heading">Excluded apps</h2>
          <p>
            {state.exclusionsAvailable
              ? "Global dictation stays off while these apps are active."
              : "App exclusions are unavailable on this desktop. Use the microphone button and Copy."}
          </p>
        </div>
        {state.exclusionsAvailable && (
          <button
            className="secondary"
            disabled={busy}
            onClick={() => void refresh()}
            aria-expanded={apps.length > 0}
          >
            <span aria-hidden="true">+ </span>Add app
          </button>
        )}
      </div>
      {state.exclusionsAvailable && apps.length > 0 && (
        <div className="exclusions-picker">
          <label htmlFor="excluded-running-app">Choose a running app</label>
          <div className="exclusions-picker-actions">
            <select
              id="excluded-running-app"
              value={selected}
              onChange={(event) => setSelected(event.target.value)}
              disabled={busy}
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
                  }).then((saved) => {
                    if (saved) setApps([]);
                  });
              }}
            >
              Exclude app
            </button>
            <button
              className="text-button"
              disabled={busy}
              onClick={() => setApps([])}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
      {error && (
        <p className="exclusions-message" role="status">{error}</p>
      )}
      {state.preferences.exclusions.length > 0 && (
        <ul className="exclusions-list">
          {state.preferences.exclusions.map((entry) => (
            <li key={entry.id}>
              <span className="excluded-app-name">
                {entry.name}
                <small>{entry.id}</small>
              </span>
              <button
                className="text-button"
                aria-label={`Remove ${entry.name} from excluded apps`}
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
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
      {state.exclusionsAvailable &&
        !state.preferences.exclusions.length && !apps.length && !error && (
          <p className="exclusions-empty">No apps excluded.</p>
        )}
    </section>
  );
}
