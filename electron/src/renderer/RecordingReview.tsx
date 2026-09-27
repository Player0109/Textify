import React, { useEffect, useMemo, useState } from "react";
import type { Action, ModelView, RecordingEntry, Snapshot } from "../shared";
import { differences, disagreement, tokens } from "../core/compare";

const mac = navigator.userAgent.includes("Mac");

// Clips that need review come first, those where the other models disagree
// most at the top, then clips not compared yet, then reviewed clips.
function rank(entries: RecordingEntry[]) {
  return entries
    .map((entry) => ({
      ...entry,
      score: disagreement(entry.modelText, Object.values(entry.comparisons)),
    }))
    .sort(
      (a, b) =>
        Number(a.correctedText !== null) - Number(b.correctedText !== null) ||
        Number(a.score === undefined) - Number(b.score === undefined) ||
        (b.score ?? 0) - (a.score ?? 0) ||
        b.id.localeCompare(a.id),
    );
}

function Marked({ text, marks }: { text: string; marks: boolean[] }) {
  return (
    <>
      {tokens(text).map((token, i) => (
        <React.Fragment key={i}>
          {i > 0 && " "}
          {marks[i] ? <mark>{token.text}</mark> : token.text}
        </React.Fragment>
      ))}
    </>
  );
}

// Each model's text for the clip, with the words the models disagree on marked.
function Outputs({
  entry,
  models,
  use,
}: {
  entry: RecordingEntry;
  models: ModelView[];
  use(text: string): void;
}) {
  const others = Object.entries(entry.comparisons).map(
    ([id, text]) => [id, text, differences(entry.modelText, text)] as const,
  );
  const disputed = tokens(entry.modelText).map((_, i) =>
    others.some(([, , result]) => result.left[i]),
  );
  const name = (id: string) =>
    models.find((model) => model.id === id)?.name ?? id;
  return (
    <div className="recording-outputs">
      {[
        [entry.modelID, entry.modelText, disputed] as const,
        ...others.map(([id, text, result]) => [id, text, result.right] as const),
      ].map(([id, text, marks]) => (
        <div className="recording-output" key={id}>
          <span>
            {name(id)}
            {id === entry.modelID && " · dictation"}
          </span>
          <p>{text ? <Marked text={text} marks={marks} /> : <em>No speech heard</em>}</p>
          <button className="text-button" disabled={!text} onClick={() => use(text)}>
            Use
          </button>
        </div>
      ))}
    </div>
  );
}

export function RecordingReview({
  state,
  run,
}: {
  state: Snapshot;
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
  }, [state.recordingsVersion]);
  const ranked = useMemo(() => rank(entries ?? []), [entries]);
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
  // Continue with the most useful clip that still needs review.
  function advance(list: RecordingEntry[]) {
    setEntries(list);
    select(rank(list).find((entry) => entry.correctedText === null));
  }
  async function change(entry: RecordingEntry, remove: boolean) {
    setBusy(true);
    setError("");
    try {
      if (remove) {
        await window.textify.deleteRecording(entry.id);
        advance(entries!.filter((item) => item.id !== entry.id));
      } else {
        await window.textify.correctRecording(entry.id, text);
        advance(
          entries!.map((item) =>
            item.id === entry.id ? { ...item, correctedText: text.trim() } : item,
          ),
        );
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
          {ranked.map((entry) => (
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
                  {entry.score !== undefined &&
                    (entry.score > 0 ? " · Models differ" : " · Models agree")}
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
                  <Outputs entry={entry} models={state.models} use={setText} />
                  <label htmlFor="recording-correction">What you said</label>
                  <textarea
                    id="recording-correction"
                    rows={3}
                    value={text}
                    disabled={busy}
                    onChange={(event) => setText(event.target.value)}
                    onKeyDown={(event) => {
                      if (event.key !== "Enter" || !(mac ? event.metaKey : event.ctrlKey))
                        return;
                      event.preventDefault();
                      if (!busy && text.trim()) void change(entry, false);
                    }}
                  />
                  <div className="recording-actions">
                    <button
                      className="text-button recording-delete"
                      disabled={busy}
                      onClick={() => void change(entry, true)}
                    >
                      Delete
                    </button>
                    <span className="recording-hint">
                      {mac ? "⌘↩" : "Ctrl+Enter"} saves and opens the next clip
                    </span>
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
