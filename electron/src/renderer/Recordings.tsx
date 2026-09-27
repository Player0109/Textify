import React, { useEffect, useState } from "react";
import type { Preferences, RecordingEntry, Snapshot } from "../shared";
export function Recordings({
  state,
  busy,
  save,
  review,
}: {
  state: Snapshot;
  busy: boolean;
  save(value: Preferences): Promise<boolean>;
  review(): void;
}) {
  const [entries, setEntries] = useState<RecordingEntry[]>([]);
  const enabled = state.preferences.saveRecordings;
  useEffect(() => {
    let active = true;
    void window.textify.recordings().then(
      (list) => active && setEntries(list),
      () => active && setEntries([]),
    );
    return () => {
      active = false;
    };
  }, [state.recordingsVersion, enabled]);
  const seconds = entries.reduce((total, entry) => total + entry.seconds, 0);
  const reviewed = entries.filter((entry) => entry.correctedText !== null).length;
  return (
    <div className="privacy-recordings">
      <span className="privacy-microphone-icon" aria-hidden="true">
        <svg
          width="26"
          height="26"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
          <path d="M8 13h1m2-2v4m2-3v2m2-1h1" />
        </svg>
      </span>
      <div>
        <h3>Save recordings for training</h3>
        <p>
          Keeps each dictation's audio and transcript in a folder on this
          device, so you can correct them and fine-tune a model.
        </p>
        {entries.length > 0 && (
          <p>
            {entries.length} saved · {reviewed} reviewed ·{" "}
            {(seconds / 60).toFixed(1)} min of audio
          </p>
        )}
      </div>
      <button className="secondary" onClick={review}>
        Review
      </button>
      <input
        type="checkbox"
        aria-label="Save recordings for training"
        checked={enabled}
        disabled={busy}
        onChange={(event) =>
          void save({ ...state.preferences, saveRecordings: event.target.checked })
        }
      />
    </div>
  );
}
