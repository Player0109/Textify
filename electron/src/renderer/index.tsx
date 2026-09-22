import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { Action, Snapshot } from "../shared";
import { startAudioRenderer } from "./audio";
import "./style.css";

const mode = new URLSearchParams(location.search).get("mode");
function Microphone() {
  return (
    <svg
      width="28"
      height="28"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      aria-hidden="true"
    >
      <rect x="9" y="2" width="6" height="13" rx="3" />
      <path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8" />
    </svg>
  );
}
function Wave({ level = 0 }: { level?: number }) {
  return (
    <span className="wave" aria-hidden="true">
      {[0.3, 0.65, 1, 0.5, 0.85, 0.4, 0.7].map((n, i) => (
        <i key={i} style={{ height: `${7 + n * (10 + level * 30)}px` }} />
      ))}
    </span>
  );
}
function useSnapshot() {
  const [state, setState] = useState<Snapshot>();
  useEffect(() => {
    const off = window.textify.subscribe(setState);
    void window.textify.snapshot().then(setState);
    return off;
  }, []);
  return state;
}
function Overlay() {
  const state = useSnapshot();
  if (!state) return null;
  const copy = state.phase === "copy";
  return (
    <div className="overlay">
      <Wave level={state.level} />
      <div className="overlay-content">
        <strong>
          {state.phase === "recording"
            ? "Listening"
            : copy
              ? "Ready to copy"
              : state.phase === "error"
                ? "Dictation stopped"
                : "Transcribing"}
        </strong>
        <span>
          {state.phase === "recording"
            ? `${state.elapsed}s · Release to finish`
            : copy
              ? "Paste into your app after copying."
              : state.message || "Processing on your device"}
        </span>
      </div>
      {copy ? (
        <button onClick={() => void window.textify.action("copy")}>Copy</button>
      ) : null}
      {["recording", "error", "copy"].includes(state.phase) && (
        <button
          className="icon-button"
          aria-label={
            state.phase === "recording" ? "Cancel dictation" : "Dismiss"
          }
          onClick={() =>
            void window.textify.action(
              state.phase === "recording" ? "cancel" : "dismiss",
            )
          }
        >
          ×
        </button>
      )}
    </div>
  );
}
const panes = ["Dictation", "Models", "Vocabulary", "Privacy"] as const;
function App() {
  const state = useSnapshot();
  const [pane, setPane] = useState<(typeof panes)[number]>("Dictation");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [devices, setDevices] = useState<{ id: string; name: string }[]>([]);
  const [trigger, setTrigger] = useState(""),
    [replacement, setReplacement] = useState("");
  useEffect(() => {
    const blur = () => {
      void window.textify.action("release");
    };
    const key = (event: KeyboardEvent) => {
      if (event.key === "Escape") void window.textify.action("cancel");
    };
    window.addEventListener("blur", blur);
    window.addEventListener("keydown", key);
    return () => {
      window.removeEventListener("blur", blur);
      window.removeEventListener("keydown", key);
    };
  }, []);
  if (!state) return <main className="loading">Opening Textify…</main>;
  const working = ["armed", "recording", "processing", "inserting"].includes(
    state.phase,
  );
  async function run(action: Action) {
    setBusy(true);
    setError("");
    try {
      await window.textify.action(action);
      if (action === "microphone") setDevices(await window.textify.devices());
    } catch {
      setError("That action could not finish. Please try again.");
    } finally {
      setBusy(false);
    }
  }
  async function save(value: Snapshot["preferences"]) {
    setError("");
    setBusy(true);
    try {
      await window.textify.preferences(value);
      return true;
    } catch {
      setError(
        "Settings could not be saved. Check for empty or duplicate replacement phrases.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  const status =
    state.phase === "recording"
      ? "Listening to you"
      : state.phase === "processing"
        ? "Transcribing locally"
        : state.ready
          ? "Ready when you are"
          : "Set up your first dictation";
  return (
    <div className="app-shell">
      <aside>
        <div className="brand">
          <span className="brand-mark">
            <Microphone />
          </span>
          <strong>Textify</strong>
        </div>
        <nav aria-label="Settings">
          {panes.map((name, i) => (
            <button
              key={name}
              aria-current={pane === name ? "page" : undefined}
              onClick={() => setPane(name)}
            >
              <span aria-hidden="true">{["◉", "▦", "Aa", "◇"][i]}</span>
              {name}
            </button>
          ))}
        </nav>
        <div className="sidebar-note">
          <span className="privacy-dot" /> On-device dictation
          <p>
            {state.platform}
            <br />
            Electron preview 0.1
          </p>
        </div>
      </aside>
      <main>
        <header>
          <div>
            <h1>{pane}</h1>
            <p>
              {pane === "Dictation"
                ? "Your voice, ready for wherever you write."
                : pane === "Models"
                  ? "Speech recognition that stays on your device."
                  : pane === "Vocabulary"
                    ? "Keep names and phrases the way you write them."
                    : "A small footprint on your private information."}
            </p>
          </div>
          <span className="offline-tag">Offline after setup</span>
        </header>
        {(error || state.message) && (
          <div className="notice" role="status">
            {error || state.message}
          </div>
        )}
        {pane === "Dictation" && (
          <>
            <section className="dictation-stage" aria-label="Record dictation">
              <div className="stage-copy">
                <div className="ready-label">
                  <span className={state.ready ? "ready-dot" : "waiting-dot"} />
                  {state.ready ? "Model ready" : "Model needed"}
                </div>
                <h2>{status}</h2>
                <p>
                  {state.ready
                    ? state.triggerStatus
                    : "Install a speech model, then allow microphone access to get started."}
                </p>
                <div className="level-row">
                  <Wave level={state.level} />
                  <span>
                    {state.phase === "recording"
                      ? `${state.elapsed}s recorded`
                      : "Hold to speak. Release to finish."}
                  </span>
                </div>
              </div>
              <button
                className={`record-button ${state.phase === "recording" ? "recording" : ""}`}
                disabled={
                  !state.ready ||
                  state.modelBusy ||
                  state.phase === "processing" ||
                  state.phase === "inserting"
                }
                aria-label="Hold to dictate"
                onPointerDown={(event) => {
                  event.currentTarget.setPointerCapture(event.pointerId);
                  void window.textify.action("press");
                }}
                onPointerUp={() => void window.textify.action("release")}
                onPointerCancel={() => void window.textify.action("cancel")}
                onKeyDown={(event) => {
                  if ([" ", "Enter"].includes(event.key)) {
                    event.preventDefault();
                    if (!event.repeat) void window.textify.action("press");
                  }
                }}
                onKeyUp={(event) => {
                  if ([" ", "Enter"].includes(event.key)) {
                    event.preventDefault();
                    void window.textify.action("release");
                  }
                }}
              >
                <Microphone />
                <span>Hold to speak</span>
              </button>
            </section>
            {state.phase === "copy" && (
              <div className="copy-row">
                <p>
                  Your latest dictation is ready. It is kept only in memory.
                </p>
                <button onClick={() => void run("copy")}>Copy dictation</button>
                <button
                  className="secondary"
                  onClick={() => void run("dismiss")}
                >
                  Dismiss
                </button>
              </div>
            )}
            <section className="settings-list">
              <div className="setting-row">
                <div>
                  <h3>Speech model</h3>
                  <p>
                    {state.ready
                      ? "Whisper small.en · English"
                      : state.modelBusy
                        ? "Preparing the model…"
                        : "One model is required to dictate."}
                  </p>
                </div>
                <button className="secondary" onClick={() => setPane("Models")}>
                  {state.ready ? "View model" : "Choose model"}
                </button>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Microphone</h3>
                  <p>
                    Audio is captured only while dictating or checking
                    permission.
                  </p>
                </div>
                <div className="control-stack">
                  <select
                    aria-label="Microphone"
                    disabled={working || busy}
                    value={state.preferences.microphone}
                    onChange={(e) =>
                      void save({
                        ...state.preferences,
                        microphone: e.target.value,
                      })
                    }
                  >
                    <option value="default">System default</option>
                    {devices
                      .filter((d) => d.id !== "default")
                      .map((d) => (
                        <option key={d.id} value={d.id}>
                          {d.name}
                        </option>
                      ))}
                    {state.preferences.microphone !== "default" &&
                      !devices.some(
                        (d) => d.id === state.preferences.microphone,
                      ) && (
                        <option value={state.preferences.microphone}>
                          Selected microphone · check availability
                        </option>
                      )}
                  </select>
                  <button
                    className="text-button"
                    disabled={busy || working}
                    onClick={() => void run("microphone")}
                  >
                    Check microphone
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Dictation trigger</h3>
                  <p>{state.triggerStatus}</p>
                </div>
                <div className="control-stack">
                  <select
                    aria-label="Dictation trigger"
                    disabled={
                      working || busy || state.platform.includes("Wayland")
                    }
                    value={state.preferences.trigger}
                    onChange={(e) =>
                      void save({
                        ...state.preferences,
                        trigger: e.target
                          .value as Snapshot["preferences"]["trigger"],
                      })
                    }
                  >
                    {state.platform === "macOS" && (
                      <option value="right-command">Right Command</option>
                    )}
                    <option value="right-control">Right Control</option>
                    <option value="control-space">Control + Space</option>
                  </select>
                  <button
                    className="text-button"
                    disabled={working || busy}
                    onClick={() => void run("enable-trigger")}
                  >
                    Enable global trigger
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Text delivery</h3>
                  <p>
                    {state.insertion === "automatic"
                      ? "Global dictation pastes into the original app. The microphone button above offers Copy."
                      : "Copy your completed dictation, then paste it into your app."}
                  </p>
                </div>
                <span className="value-label">
                  {state.insertion === "automatic"
                    ? "Automatic paste"
                    : "Copy and paste"}
                </span>
              </div>
            </section>
            <p className="footnote">
              {state.platform.includes("Wayland")
                ? "Use Cancel in the recording indicator to cancel."
                : "Press Esc to cancel a recording."}{" "}
              Each recording is limited to five minutes.
            </p>
          </>
        )}
        {pane === "Models" && (
          <>
            <section className="model-card">
              <div className="model-top">
                <span className="model-symbol">
                  <Wave />
                </span>
                <div>
                  <h2>Whisper small.en</h2>
                  <p>English speech recognition</p>
                </div>
                <span className="model-state">
                  {state.ready
                    ? "Ready"
                    : state.models[0]?.installed
                      ? "Installed"
                      : "Not installed"}
                </span>
              </div>
              <p className="model-description">
                A compact model for everyday English dictation. Download it once
                and use it offline.
              </p>
              <dl>
                <div>
                  <dt>Download</dt>
                  <dd>190 MB</dd>
                </div>
                <div>
                  <dt>Language</dt>
                  <dd>English</dd>
                </div>
                <div>
                  <dt>License</dt>
                  <dd>MIT</dd>
                </div>
                <div>
                  <dt>Publisher</dt>
                  <dd>OpenAI</dd>
                </div>
              </dl>
              {state.download !== null && (
                <div className="download">
                  <progress value={state.download} max={1} />
                  <span>{Math.round(state.download * 100)}%</span>
                </div>
              )}
              <div className="model-actions">
                <button
                  disabled={busy || working || state.modelBusy || state.ready}
                  onClick={() => void run("download")}
                >
                  {state.modelBusy
                    ? "Preparing…"
                    : state.ready
                      ? "Model ready"
                      : "Download model"}
                </button>
                {state.download !== null ? (
                  <button
                    className="secondary"
                    onClick={() =>
                      void window.textify.action("cancel-download")
                    }
                  >
                    Cancel download
                  </button>
                ) : (
                  <button
                    className="secondary"
                    disabled={busy || working || state.modelBusy}
                    onClick={() => void run("import")}
                  >
                    Use existing model file
                  </button>
                )}
              </div>
            </section>
            <p className="footnote">
              Downloads and imports are checked against the bundled signed
              catalog. Existing files must match the exact Whisper small.en
              model. Additional models will be migrated separately.
            </p>
          </>
        )}
        {pane === "Vocabulary" && (
          <section className="vocabulary">
            <h2>Replacement pairs</h2>
            <p>
              Replace a spoken word or phrase with the exact text you choose.
            </p>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                if (trigger.trim() && replacement.trim())
                  void save({
                    ...state.preferences,
                    replacements: [
                      ...state.preferences.replacements,
                      { trigger, replacement },
                    ],
                  }).then((saved) => {
                    if (saved) {
                      setTrigger("");
                      setReplacement("");
                    }
                  });
              }}
            >
              <label>
                When I say
                <input
                  required
                  maxLength={200}
                  value={trigger}
                  onChange={(e) => setTrigger(e.target.value)}
                  placeholder="text if eye"
                />
              </label>
              <label>
                Replace with
                <input
                  required
                  maxLength={1000}
                  value={replacement}
                  onChange={(e) => setReplacement(e.target.value)}
                  placeholder="Textify"
                />
              </label>
              <button disabled={working || busy}>Add pair</button>
            </form>
            {state.preferences.replacements.length ? (
              <ul>
                {state.preferences.replacements.map((pair, i) => (
                  <li key={pair.trigger}>
                    <span>{pair.trigger}</span>
                    <strong>{pair.replacement}</strong>
                    <button
                      className="text-button"
                      disabled={working || busy}
                      onClick={() =>
                        void save({
                          ...state.preferences,
                          replacements: state.preferences.replacements.filter(
                            (_, index) => index !== i,
                          ),
                        })
                      }
                    >
                      Remove
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="empty">
                <strong>No replacement pairs yet</strong>
                <p>Add names, abbreviations, or phrases you use often.</p>
              </div>
            )}
          </section>
        )}
        {pane === "Privacy" && (
          <section className="privacy">
            <div className="privacy-intro">
              <span className="privacy-symbol">◇</span>
              <h2>Your speech stays here.</h2>
              <p>
                Textify processes audio on this device. There are no accounts,
                analytics, or transcript uploads.
              </p>
            </div>
            <div className="settings-list">
              <div className="setting-row">
                <div>
                  <h3>Microphone permission</h3>
                  <p>
                    Requested when you check the microphone or start dictating.
                  </p>
                </div>
                <button
                  className="secondary"
                  disabled={working || busy}
                  onClick={() => void run("microphone")}
                >
                  Check microphone
                </button>
              </div>
              {state.platform === "macOS" && (
                <div className="setting-row">
                  <div>
                    <h3>Accessibility permission</h3>
                    <p>Needed for global keys and pasting into another app.</p>
                  </div>
                  <button
                    className="secondary"
                    onClick={() => void run("permissions")}
                  >
                    Open settings
                  </button>
                </div>
              )}
              <div className="setting-row">
                <div>
                  <h3>Audio and dictated text</h3>
                  <p>
                    Audio stays in memory. No recordings or transcript history
                    are saved.
                  </p>
                </div>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Clipboard</h3>
                  <p>
                    Automatic insertion restores the previous clipboard when it
                    has not changed. Explicit Copy replaces it until you copy
                    something else.
                  </p>
                </div>
              </div>
            </div>
            <p className="footnote">
              Network access is used only when you choose to download a model.
              Model hosts receive normal download request information.
            </p>
          </section>
        )}
      </main>
    </div>
  );
}
if (mode === "audio") startAudioRenderer();
else {
  document.body.classList.toggle("overlay-page", mode === "overlay");
  createRoot(document.getElementById("root")!).render(
    mode === "overlay" ? <Overlay /> : <App />,
  );
}
