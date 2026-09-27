import React, { useEffect, useState } from "react";
import type { Action, RecordingEntry, Snapshot } from "../shared";
export function RecordingReview({
  phase,
  run,
}: {
  phase: Snapshot["phase"];
  run(action: Action): Promise<void>;
}) {
  const [entries, setEntries] = useState<RecordingEntry[]>();
  const [open, setOpen] = useState<string>();
  const [text, setText] = useState("");
  const [audio, setAudio] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    void window.textify.recordings().then(
      (list) => active && setEntries(list),
      () => {
        if (!active) return;
        setEntries([]);
        setError("Recordings could not be read.");
      },
    );
    return () => {
      active = false;
    };
  }, [phase]);
  useEffect(() => {
    if (!open) return;
    let url: string | undefined;
    let current = true;
    window.textify.recordingAudio(open).then(
      (bytes) => {
        if (!current) return;
        url = URL.createObjectURL(new Blob([bytes], { type: "audio/wav" }));
        setAudio(url);
      },
      () => current && setError("This recording's audio could not be read."),
    );
    return () => {
      current = false;
      if (url) URL.revokeObjectURL(url);
      setAudio(undefined);
    };
  }, [open]);
  function select(entry?: RecordingEntry) {
    setOpen(entry?.id);
    setText(entry ? (entry.correctedText ?? entry.modelText) : "");
    setError("");
  }
  // Continue with the next clip that still needs review, wrapping to the top.
  function advance(list: RecordingEntry[], index: number) {
    setEntries(list);
    select(
      [...list.slice(index), ...list.slice(0, index)].find(
        (entry) => entry.correctedText === null,
      ),
    );
  }
  async function change(entry: RecordingEntry, remove: boolean) {
    setBusy(true);
    setError("");
    try {
      const index = entries!.indexOf(entry);
      if (remove) {
        await window.textify.deleteRecording(entry.id);
        advance(entries!.filter((item) => item !== entry), index);
      } else {
        await window.textify.correctRecording(entry.id, text);
        const list = entries!.map((item) =>
          item === entry ? { ...item, correctedText: text.trim() } : item,
        );
        advance(list, index + 1);
      }
    } catch {
      setError(
        remove
          ? "The recording could not be deleted."
          : "The correction could not be saved.",
      );
    } finally {
      setBusy(false);
    }
  }
  const reviewed = entries?.filter((entry) => entry.correctedText !== null);
  const seconds = entries?.reduce((total, entry) => total + entry.seconds, 0);
  return (
    <section className="recording-review">
      <div className="recording-toolbar">
        {entries && (
          <p>
            {entries.length} saved · {reviewed!.length} reviewed ·{" "}
            {(seconds! / 60).toFixed(1)} min of audio
          </p>
        )}
        <button
          className="text-button"
          onClick={() => void run("reveal-recordings")}
        >
          Show folder
        </button>
      </div>
      {error && (
        <p className="recording-message" role="status">
          {error}
        </p>
      )}
      {entries?.length === 0 && (
        <p className="recording-empty">
          No recordings yet. Turn on Save recordings for training in Privacy,
          then dictate.
        </p>
      )}
      {!!entries?.length && (
        <ul className="recording-list">
          {entries.map((entry) => (
            <li key={entry.id}>
              <button
                className="recording-row"
                aria-expanded={entry.id === open}
                onClick={() => select(entry.id === open ? undefined : entry)}
              >
                <span className="recording-text">
                  {entry.correctedText ?? entry.modelText}
                </span>
                <span className="recording-meta">
                  {new Date(entry.createdAt).toLocaleString(undefined, {
                    dateStyle: "medium",
                    timeStyle: "short",
                  })}{" "}
                  · {entry.seconds.toFixed(1)} s
                </span>
                <span
                  className={
                    entry.correctedText === null
                      ? "recording-status"
                      : "recording-status reviewed"
                  }
                >
                  {entry.correctedText === null ? "Needs review" : "Reviewed"}
                </span>
              </button>
              {entry.id === open && (
                <div className="recording-editor">
                  <audio controls autoPlay src={audio} />
                  {entry.correctedText !== null && (
                    <p className="recording-heard">
                      Model heard: {entry.modelText}
                    </p>
                  )}
                  <label htmlFor="recording-correction">What you said</label>
                  <textarea
                    id="recording-correction"
                    rows={3}
                    value={text}
                    disabled={busy}
                    onChange={(event) => setText(event.target.value)}
                  />
                  <div className="recording-actions">
                    <button
                      className="text-button recording-delete"
                      disabled={busy}
                      onClick={() => void change(entry, true)}
                    >
                      Delete
                    </button>
                    <button
                      disabled={busy || !text.trim()}
                      onClick={() => void change(entry, false)}
                    >
                      Save
                    </button>
                  </div>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
