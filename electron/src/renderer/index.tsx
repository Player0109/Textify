import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { Action, Snapshot, ModelCommand } from "../shared";
import { startAudioRenderer } from "./audio";
import "./style.css";
import "./studio.css";
import { LANGUAGES } from "../shared";
import { ModelsPane } from "./ModelsPane";
import { Overlay } from "./Overlay";
import { FloatingIconSettings } from "./FloatingIconSettings";
import { AccessibilitySetup } from "./AccessibilitySetup";
import { AccessibilityDragHelp } from "./AccessibilityDragHelp";
import { CustomWords } from "./CustomWords";
import { Exclusions } from "./Exclusions";
import { ActivityPane } from "./ActivityPane";
import textifyIcon from "../../assets/textify-icon.png";

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
      {[0.38, 0.68, 1, 0.58, 0.32].map((n, i) => (
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
function FloatingBar() {
  const state = useSnapshot();
  return state ? <Overlay state={state} /> : null;
}
function NavIcon({ name }: { name: string }) {
  return (
    <svg
      width="17"
      height="17"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.65"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {name === "Models" ? (
        <>
          <path d="M3 10v4m4-8v12m4-15v18m4-13v8m4-11v14m4-9v4" />
        </>
      ) : name === "Activity" ? (
        <>
          <path d="M3 19h18M5 16V9m5 7V5m5 11v-4m5 4V7" />
        </>
      ) : name === "Vocabulary" ? (
        <>
          <path d="M12 20c-2-1.5-5-2.2-9-1.8V4.5c4-.4 7 .3 9 1.8m0 13.7c2-1.5 5-2.2 9-1.8V4.5c-4-.4-7 .3-9 1.8M12 6.3V20" />
        </>
      ) : name === "Privacy" ? (
        <>
          <path d="M12 2 4 6v6c0 5 8 10 8 10s8-5 8-10V6z" />
          <path d="m8 12 3 3 5-6" />
        </>
      ) : (
        <>
          <circle cx="12" cy="12" r="3" />
          <path d="M10 2h4l.5 2.4 1.8.8 2.1-1.1 2.8 2.8-1.1 2.1.8 1.8L23 11v4l-2.4.5-.8 1.8 1.1 2.1-2.8 2.8-2.1-1.1-1.8.8L14 23h-4l-.5-2.4-1.8-.8-2.1 1.1-2.8-2.8 1.1-2.1-.8-1.8L1 15v-4l2.4-.5.8-1.8-1.1-2.1 2.8-2.8 2.1 1.1 1.8-.8z" />
        </>
      )}
    </svg>
  );
}
const panes = ["General", "Models", "Vocabulary", "Activity", "Privacy"] as const;
function App() {
  const state = useSnapshot();
  const [pane, setPane] = useState<(typeof panes)[number]>("General");
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
  const dictating = ["armed", "recording", "processing", "inserting"].includes(state.phase);
  const working = state.modelBusy || dictating;
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
        "Settings could not be saved. Check for invalid or duplicate values, and finish any active dictation first.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  async function runModel(command: ModelCommand) {
    const changesModel = command.action !== "source";
    if (changesModel) setBusy(true);
    setError("");
    try {
      await window.textify.model(command);
    } catch {
      setError(
        command.action === "source"
          ? "The model page could not open. Try the link again."
          : "The model action could not finish. Check the model status, available storage, and selected language.",
      );
    } finally {
      if (changesModel) setBusy(false);
    }
  }
  const activeModel = state.models.find(
    (model) => model.id === state.preferences.activeModelID,
  );
  const status =
    state.phase === "recording"
      ? "Listening to you"
      : state.phase === "processing"
        ? "Transcribing locally"
        : state.modelBusy
          ? "Preparing your model"
          : state.ready
            ? "Ready when you are"
            : "Set up your first dictation";
  return (
    <div className="app-shell studio">
      <aside>
        <div className="brand">
          <img className="brand-mark" src={textifyIcon} alt="" />
          <div className="brand-copy">
            <strong>Textify</strong>
          </div>
        </div>
        <nav aria-label="Settings">
          {panes.map((name) => (
            <button
              key={name}
              aria-current={pane === name ? "page" : undefined}
              onClick={() => setPane(name)}
            >
              <span aria-hidden="true">
                <NavIcon name={name} />
              </span>
              {name === "Models" ? "Transcription models" : name}
            </button>
          ))}
        </nav>
      </aside>
      <main className={pane === "Models" ? "models-main" : undefined}>
        <header>
          <div>
            <h1>{pane === "Models" ? "Transcription models" : pane}</h1>
            {pane === "Vocabulary" && (
              <p>
                Custom words apply to Whisper models. Replacement pairs work
                with every model.
              </p>
            )}
            {pane === "Activity" && <p>Your dictation activity, saved on this device.</p>}
          </div>
        </header>
        {(error || state.message) && (
          <div className="notice" role="status">
            {error || state.message}
          </div>
        )}
        {pane === "General" && (
          <>
            {state.accessibility && state.accessibility.status !== "granted" && (
              <AccessibilitySetup state={state} busy={busy || dictating} run={run} />
            )}
            <section className={`dictation-stage ${state.phase === "recording" ? "is-recording" : ""}`} aria-label="Record dictation">
              <div className="stage-copy">
                <div className="ready-label">
                  <span className={state.ready ? "ready-dot" : "waiting-dot"} />
                  {state.ready ? "GPU ready" : "Dictation unavailable"}
                </div>
                <h2>{status}</h2>
                <p>
                  {state.ready
                    ? state.triggerStatus
                    : "Dictation requires a supported GPU and an installed speech model."}
                </p>
                {state.ready && activeModel && (
                  <p className="stage-model">Using <strong>{activeModel.name}</strong></p>
                )}
                {state.phase === "recording" && (
                  <div className="level-row">
                    <Wave level={state.level} />
                    <span>{state.elapsed}s recorded</span>
                  </div>
                )}
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
                  <p>{state.ready
                    ? activeModel?.name
                    : state.modelBusy
                      ? "Preparing the model…"
                      : "One model is required to dictate."}</p>
                </div>
                <button className="secondary" onClick={() => setPane("Models")}>
                  {state.ready ? "View model" : "Choose model"}
                </button>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Dictation language</h3>
                </div>
                <select
                  aria-label="Dictation language"
                  disabled={working || busy || state.modelBusy}
                  value={state.preferences.language}
                  onChange={(event) =>
                    void save({
                      ...state.preferences,
                      language: event.target.value,
                    })
                  }
                >
                  {(activeModel?.languages ?? ["en"]).map((code) => (
                    <option key={code} value={code}>
                      {LANGUAGES[code] ?? code}
                    </option>
                  ))}
                  {!activeModel?.languages.includes(
                    state.preferences.language,
                  ) && (
                    <option value={state.preferences.language}>
                      {LANGUAGES[state.preferences.language]} · choose a
                      compatible model
                    </option>
                  )}
                </select>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Microphone</h3>
                </div>
                <div className="control-stack microphone-control">
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
                      <>
                        <option value="right-command">Right Command</option>
                        <option value="right-option">Right Option</option>
                      </>
                    )}
                    <option value="right-control">Right Control</option>
                    <option value="control-space">Control + Space</option>
                  </select>
                  {!state.triggerEnabled && (!state.accessibility || state.accessibility.status === "granted") && (
                    <button
                      className="text-button"
                      disabled={working || busy}
                      onClick={() => void run("enable-trigger")}
                    >
                      Enable global trigger
                    </button>
                  )}
                </div>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Text delivery</h3>
                </div>
                <span className="value-label">
                  {state.insertion === "automatic"
                    ? "Automatic paste"
                    : "Copy and paste"}
                </span>
              </div>
              <div className="setting-row">
                <div>
                  <h3>Launch at login</h3>
                </div>
                <input
                  type="checkbox"
                  aria-label="Launch at login"
                  checked={state.preferences.launchAtLogin}
                  disabled={working || busy || !state.startupAvailable}
                  onChange={(event) =>
                    void save({
                      ...state.preferences,
                      launchAtLogin: event.target.checked,
                    })
                  }
                />
              </div>
            </section>
            <FloatingIconSettings
              preferences={state.preferences}
              busy={working || busy}
              save={save}
            />
            <p className="footnote">
              {state.platform.includes("Wayland")
                ? "Use Cancel in the recording indicator to cancel."
                : "Press Esc to cancel a recording."}{" "}
              Each recording is limited to five minutes.
            </p>
          </>
        )}
        {pane === "Models" && (
          <ModelsPane
            state={state}
            // While a model loads, the snapshot decides which buttons lock.
            busy={dictating || (busy && !state.modelBusy)}
            run={runModel}
          />
        )}
        {pane === "Vocabulary" && (
          <div className="vocabulary-grid">
            <CustomWords
              preferences={state.preferences}
              busy={working || busy || state.modelBusy}
              save={save}
            />
            <section className="vocabulary vocabulary-panel">
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
                <div className="vocabulary-empty">No replacement pairs yet</div>
              )}
            </section>
          </div>
        )}
        {pane === "Activity" && <ActivityPane phase={state.phase} />}
        {pane === "Privacy" && (
          <section className="privacy">
            <div className="privacy-intro">
              <h2>Your speech stays here.</h2>
              <p>
                Textify processes speech on this device. No recordings or
                transcript history are saved.
              </p>
            </div>
            <div className="privacy-workspace">
              <AccessibilitySetup state={state} busy={busy || dictating} run={run} />
              <div className="privacy-microphone">
                <span className="privacy-microphone-icon"><Microphone /></span>
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
              <Exclusions state={state} busy={working || busy} save={save} />
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
  document.documentElement.classList.toggle("overlay-page", mode === "overlay");
  document.body.classList.toggle("overlay-page", mode === "overlay");
  document.documentElement.classList.toggle("accessibility-help-page", mode === "accessibility-help");
  document.body.classList.toggle("accessibility-help-page", mode === "accessibility-help");
  createRoot(document.getElementById("root")!).render(
    mode === "overlay" ? <FloatingBar /> : mode === "accessibility-help" ? <AccessibilityDragHelp /> : <App />,
  );
}
