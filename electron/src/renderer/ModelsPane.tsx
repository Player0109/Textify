import React from "react";
import { LANGUAGES, type ModelCommand, type Snapshot } from "../shared";
export function ModelsPane({
  state,
  busy,
  run,
}: {
  state: Snapshot;
  busy: boolean;
  run(command: ModelCommand): Promise<void>;
}) {
  return (
    <div className="model-list">
      {state.models.map((model) => {
        const active = model.id === state.preferences.activeModelID;
        const transferring = state.downloadModelID === model.id;
        const locked = busy || state.modelBusy;
        return (
          <section
            className="model-card"
            key={model.id}
            aria-label={model.name}
          >
            <div className="model-top">
              <div>
                <h2>{model.name}</h2>
                <p>
                  {model.languages
                    .map((code) => LANGUAGES[code] ?? code)
                    .join(" · ")}
                </p>
              </div>
              <span className="model-state">
                {model.status === "revoked"
                  ? "Revoked"
                  : model.status === "verify-required"
                    ? "Verification required"
                    : active && state.ready
                      ? "Active"
                      : model.installed
                        ? "Installed"
                        : "Not installed"}
              </span>
            </div>
            <p className="model-description">
              {model.id === "ggml-small.en-q5_1"
                ? "A compact model for everyday English dictation."
                : model.id.includes("turbo")
                  ? "A larger model with English and Hindi support in this preview."
                  : "A larger Whisper model for English dictation in this preview."}{" "}
              Speech is processed on this device.
            </p>
            <dl>
              <div>
                <dt>Download</dt>
                <dd>
                  {model.bytes > 1e9
                    ? `${(model.bytes / 1e9).toFixed(2)} GB`
                    : `${Math.round(model.bytes / 1e6)} MB`}
                </dd>
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
            {transferring && state.download !== null && (
              <div className="download">
                <progress value={state.download} max={1} />
                <span>{Math.round(state.download * 100)}%</span>
              </div>
            )}
            <div className="model-actions">
              {model.status !== "revoked" &&
                (model.installed ? (
                  <button
                    disabled={locked || (active && state.ready)}
                    onClick={() =>
                      void run({
                        action:
                          model.status === "verify-required" ? "verify" : "use",
                        id: model.id,
                      })
                    }
                  >
                    {model.status === "verify-required"
                      ? "Verify model"
                      : active && state.ready
                        ? "Active model"
                        : "Use model"}
                  </button>
                ) : (
                  <button
                    disabled={locked}
                    onClick={() =>
                      void run({ action: "download", id: model.id })
                    }
                  >
                    {model.resumable ? "Resume download" : "Download model"}
                  </button>
                ))}
              {transferring ? (
                <button
                  className="secondary"
                  onClick={() => void window.textify.action("cancel-download")}
                >
                  Pause download
                </button>
              ) : (
                <>
                  {model.status !== "revoked" && (
                    <button
                      className="secondary"
                      disabled={locked}
                      onClick={() =>
                        void run({ action: "import", id: model.id })
                      }
                    >
                      Use existing model file
                    </button>
                  )}
                  {model.storedBytes > 0 && (
                    <button
                      className="text-button"
                      disabled={locked}
                      onClick={() =>
                        void run({ action: "remove", id: model.id })
                      }
                    >
                      Remove files
                    </button>
                  )}
                </>
              )}
            </div>
          </section>
        );
      })}
      <p className="footnote">
        Downloads and imports must match the signed catalog exactly. Paused
        downloads resume from verified partial files. Revoked models cannot be
        used; restored models require explicit verification. Other model
        runtimes are not included in this preview.
      </p>
    </div>
  );
}
