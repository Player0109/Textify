import React, { useState } from "react";
import type { Preferences, Snapshot } from "../shared";
export function GeneralPane({
  state,
  busy,
  save,
}: {
  state: Snapshot;
  busy: boolean;
  save(value: Preferences): Promise<boolean>;
}) {
  const [preview, setPreview] = useState<{
    preferences: Preferences;
    notes: string[];
  } | null>(null);
  const [error, setError] = useState("");
  return (
    <section className="settings-list">
      <div className="setting-row">
        <div>
          <h3>Launch at login</h3>
          <p>
            {state.startupAvailable
              ? "Open Textify in the background when you sign in."
              : "Available after installing the packaged app."}
          </p>
        </div>
        <input
          type="checkbox"
          aria-label="Launch at login"
          checked={state.preferences.launchAtLogin}
          disabled={busy || !state.startupAvailable}
          onChange={(event) =>
            void save({
              ...state.preferences,
              launchAtLogin: event.target.checked,
            })
          }
        />
      </div>
      <div className="setting-row">
        <div>
          <h3>Recording indicator</h3>
          <p>Adjust its position and size. It stays within the screen.</p>
        </div>
        <button
          className="secondary"
          disabled={busy}
          onClick={() =>
            void save({
              ...state.preferences,
              overlay: { x: 0, y: 0, scale: 1 },
            })
          }
        >
          Reset indicator
        </button>
      </div>
      <div className="overlay-settings">
        {(
          [
            ["x", "Horizontal offset", -2000, 2000, 10],
            ["y", "Vertical offset", -2000, 2000, 10],
            ["scale", "Scale", 0.5, 2, 0.1],
          ] as const
        ).map(([key, label, min, max, step]) => (
          <label key={key}>
            {label}
            <input
              aria-label={label}
              type="number"
              min={min}
              max={max}
              step={step}
              disabled={busy}
              key={state.preferences.overlay[key]}
              defaultValue={state.preferences.overlay[key]}
              onBlur={(event) => {
                const value = Number(event.target.value);
                if (
                  value !== state.preferences.overlay[key] &&
                  Number.isFinite(value)
                )
                  void save({
                    ...state.preferences,
                    overlay: { ...state.preferences.overlay, [key]: value },
                  });
              }}
            />
          </label>
        ))}
      </div>
      <div className="setting-row">
        <div>
          <h3>Import native Textify settings</h3>
          <p>
            Review the supported settings before applying them. The source file
            is kept.
          </p>
        </div>
        <button
          className="secondary"
          disabled={busy}
          onClick={() => {
            setError("");
            void window.textify
              .importSettings()
              .then(setPreview)
              .catch(() =>
                setError("Choose a valid native Textify settings.json file."),
              );
          }}
        >
          Choose settings file
        </button>
      </div>
      {error && <p role="status">{error}</p>}
      {preview && (
        <div className="import-preview">
          <h3>Settings to import</h3>
          <p>
            Trigger: {preview.preferences.trigger}
            <br />
            Language: {preview.preferences.language}
            <br />
            Model: {preview.preferences.activeModelID}
            <br />
            Excluded apps: {preview.preferences.exclusions.length}
          </p>
          {preview.notes.map((note) => (
            <p key={note}>{note}</p>
          ))}
          <div className="model-actions">
            <button
              disabled={busy}
              onClick={() =>
                void save(preview.preferences).then((saved) => {
                  if (saved) setPreview(null);
                })
              }
            >
              Apply imported settings
            </button>
            <button className="secondary" onClick={() => setPreview(null)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
