import React, { useState } from "react";
import {
  LANGUAGES,
  type ModelCommand,
  type ModelView,
  type Snapshot,
} from "../shared";
const size = (bytes: number) =>
  bytes >= 1e9
    ? `${(bytes / 1e9).toFixed(2)} GB`
    : `${Math.round(bytes / 1e6)} MB`;
const engineName = {
  whisper_cpp: "whisper.cpp",
  transcribe_cpp: "transcribe.cpp",
  audio_cpp: "audio.cpp",
};
function status(model: ModelView, state: Snapshot) {
  if (model.status === "revoked") return "Revoked";
  if (model.status === "verify-required") return "Verify files";
  if (model.id === state.preferences.activeModelID && state.ready)
    return "In use";
  return model.installed ? "Installed" : "Not installed";
}
export function ModelsPane({
  state,
  busy,
  run,
}: {
  state: Snapshot;
  busy: boolean;
  run(command: ModelCommand): Promise<void>;
}) {
  const active = state.models.find(
    (m) => m.id === state.preferences.activeModelID,
  );
  const [selected, select] = useState(
    active?.checkpointID ?? state.models[0]?.checkpointID,
  );
  const [query, setQuery] = useState("");
  const [language, setLanguage] = useState("");
  const [installedOnly, setInstalledOnly] = useState(false);
  const checkpoints = Array.from(
    new Set(state.models.map((m) => m.checkpointID)),
  ).map((id) => state.models.filter((m) => m.checkpointID === id));
  const filtered = checkpoints.filter((variants) => {
    const m = variants[0];
    return (
      `${m.name} ${m.provider}`.toLowerCase().includes(query.toLowerCase()) &&
      (!language || m.languages.includes(language)) &&
      (!installedOnly || variants.some((v) => v.installed))
    );
  });
  const visible =
    filtered.find((variants) => variants[0].checkpointID === selected) ??
    filtered[0];
  const checkpoint = visible?.[0];
  const locked = busy || state.modelBusy;
  const languages = [...new Set(state.models.flatMap((m) => m.languages))]
    .filter((l) => l !== "auto")
    .sort((a, b) => (LANGUAGES[a] ?? a).localeCompare(LANGUAGES[b] ?? b));
  return (
    <div className="model-browser">
      <div className="catalog-toolbar">
        <div className="search-field">
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.7"
            aria-hidden="true"
          >
            <circle cx="10" cy="10" r="6" />
            <path d="m15 15 5 5" />
          </svg>
          <input
            type="search"
            aria-label="Search models"
            placeholder="Search models"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <select
          aria-label="Filter models by language"
          value={language}
          onChange={(e) => setLanguage(e.target.value)}
        >
          <option value="">All languages</option>
          {languages.map((l) => (
            <option key={l} value={l}>
              {LANGUAGES[l] ?? l}
            </option>
          ))}
        </select>
        <button
          className={`filter-button ${installedOnly ? "selected" : ""}`}
          aria-pressed={installedOnly}
          onClick={() => setInstalledOnly(!installedOnly)}
        >
          Installed
        </button>
      </div>
      <div className="catalog-layout">
        <div className="checkpoint-list" aria-label="Model checkpoints">
          <div className="catalog-count">{filtered.length} checkpoints</div>
          {filtered.map((variants) => {
            const model = variants[0],
              inUse = variants.some((v) => v.id === active?.id && state.ready);
            return (
              <button
                key={model.checkpointID}
                className={`checkpoint-row ${checkpoint?.checkpointID === model.checkpointID ? "selected" : ""}`}
                aria-pressed={checkpoint?.checkpointID === model.checkpointID}
                onClick={() => select(model.checkpointID)}
              >
                <span className="checkpoint-provider">{model.provider}</span>
                <strong>{model.name}</strong>
                <span className="checkpoint-description">
                  {model.description}
                </span>
                <span className="checkpoint-footer">
                  <span>
                    {variants.length}{" "}
                    {variants.length === 1 ? "version" : "versions"}
                  </span>
                  {inUse ? (
                    <span className="in-use">● In use</span>
                  ) : (
                    <span>
                      {variants.some((v) => v.installed)
                        ? "Installed"
                        : `From ${size(Math.min(...variants.map((v) => v.bytes)))}`}
                    </span>
                  )}
                </span>
              </button>
            );
          })}
          {!filtered.length && (
            <div className="catalog-empty">
              No matching models.
              <br />
              Try another search or language.
            </div>
          )}
        </div>
        {checkpoint && (
          <section
            className="checkpoint-detail"
            aria-label={`${checkpoint.name} details`}
          >
            <div className="section-caption accent">Checkpoint</div>
            <h2>{checkpoint.name}</h2>
            <p className="checkpoint-summary">{checkpoint.description}</p>
            <section className="inspector-section">
              <h3 className="section-caption">Overview</h3>
              <dl className="model-facts">
                <div>
                  <dt>Purpose</dt>
                  <dd>Speech recognition</dd>
                </div>
                <div>
                  <dt>Provider</dt>
                  <dd>{checkpoint.provider}</dd>
                </div>
                <div>
                  <dt>Languages</dt>
                  <dd>
                    {checkpoint.languages
                      .filter((l) => l !== "auto")
                      .map((l) => LANGUAGES[l] ?? l)
                      .join(", ")}
                  </dd>
                </div>
                <div>
                  <dt>Processing</dt>
                  <dd>
                    On-device GPU
                    {state.platform === "macOS" ? " · Metal" : " · Vulkan"}
                  </dd>
                </div>
              </dl>
            </section>
            <section className="inspector-section">
              <h3 className="section-caption">Versions</h3>
              {visible.map((model) => {
                const transferring = state.downloadModelID === model.id;
                const using = model.id === active?.id && state.ready;
                return (
                  <div
                    className={`variant ${using ? "variant-active" : ""}`}
                    key={model.id}
                  >
                    <div className="variant-heading">
                      <span className="variant-radio" aria-hidden="true">
                        {using ? "●" : "○"}
                      </span>
                      <div>
                        <h4>{model.variant}</h4>
                        <p>
                          {engineName[model.engine]} · {size(model.bytes)}
                        </p>
                      </div>
                      <span className={`model-state ${using ? "in-use" : ""}`}>
                        {status(model, state)}
                      </span>
                    </div>
                    {transferring && state.download !== null && (
                      <div className="download">
                        <progress value={state.download} max={1} />
                        <span>{Math.round(state.download * 100)}%</span>
                      </div>
                    )}
                    <div className="model-actions">
                      {model.status !== "revoked" && (
                        <button
                          disabled={locked || using}
                          onClick={() =>
                            void run({
                              action: model.installed
                                ? model.status === "verify-required"
                                  ? "verify"
                                  : "use"
                                : "download",
                              id: model.id,
                            })
                          }
                        >
                          {model.installed
                            ? model.status === "verify-required"
                              ? "Verify model"
                              : using
                                ? "In use"
                                : "Use model"
                            : model.resumable
                              ? "Resume download"
                              : "Download"}
                        </button>
                      )}
                      {transferring ? (
                        <button
                          className="secondary"
                          onClick={() =>
                            void window.textify.action("cancel-download")
                          }
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
                              Import file
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
                              Remove
                            </button>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                );
              })}
            </section>
            <section className="inspector-section">
              <h3 className="section-caption">Source &amp; license</h3>
              <dl className="model-facts">
                <div>
                  <dt>Model license</dt>
                  <dd>{checkpoint.license}</dd>
                </div>
                <div>
                  <dt>Original model</dt>
                  <dd className="source-url">{checkpoint.source}</dd>
                </div>
                <div>
                  <dt>Verification</dt>
                  <dd>Signed catalog · SHA-256 checked</dd>
                </div>
              </dl>
              <p className="footnote">
                Quality and speed have not been rated for this Electron runtime.{" "}
                {checkpoint.engine === "audio_cpp"
                  ? "This version returns final text on release; live previews are not included."
                  : ""}
              </p>
            </section>
          </section>
        )}
      </div>
      <p className="footnote">
        Models stay on this device after download. Import an existing file to
        avoid downloading it again. Only verified files can be used.
      </p>
    </div>
  );
}
