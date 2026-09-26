import React, { useState } from "react";
import {
  LANGUAGES,
  type ModelCommand,
  type ModelView,
  type Snapshot,
} from "../shared";
import openaiLogo from "../../assets/model-providers/openai.webp";
import nvidiaLogo from "../../assets/model-providers/nvidia-dark.png";
import qwenLogo from "../../assets/model-providers/qwen.png";
import youdaoLogo from "../../assets/model-providers/youdao.png";

const providerLogos: Record<string, { image: string; style: string }> = {
  OpenAI: { image: openaiLogo, style: "openai" },
  NVIDIA: { image: nvidiaLogo, style: "nvidia" },
  Qwen: { image: qwenLogo, style: "qwen" },
  "NetEase Youdao": { image: youdaoLogo, style: "youdao" },
};

function ProviderLogo({ provider }: { provider: string }) {
  const logo = providerLogos[provider];
  return (
    <span className={`provider-logo ${logo ? `provider-logo--${logo.style}` : ""}`} aria-hidden="true">
      {logo ? <img src={logo.image} alt="" /> : provider.slice(0, 2).toUpperCase()}
    </span>
  );
}

const size = (bytes: number) =>
  bytes >= 1e9
    ? `${(bytes / 1e9).toFixed(2)} GB`
    : `${Math.round(bytes / 1e6)} MB`;
const languageNames = (model: ModelView) =>
  model.languages.filter((l) => l !== "auto").map((l) => LANGUAGES[l] ?? l);
function status(model: ModelView, state: Snapshot) {
  if (model.status === "revoked") return "Revoked";
  if (model.status === "verify-required") return "Verify files";
  if (model.id === state.preferences.activeModelID && state.ready)
    return "In use";
  return model.installed ? "Installed" : "";
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
  const [expandedVersion, expandVersion] = useState<string | null>(null);
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
  // Loading the active model does not stop another model's download or import.
  const installLocked = busy || state.modelStorageBusy;
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
        <div className="checkpoint-list" aria-label="Models">
          <div className="catalog-count sr-only">
            {filtered.length} {filtered.length === 1 ? "model" : "models"}
          </div>
          <div className="catalog-columns" aria-hidden="true">
            <span>Model</span>
            <span>Languages</span>
            <span>Status</span>
          </div>
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
                <span className="checkpoint-identity">
                  <ProviderLogo provider={model.provider} />
                  <strong>{model.name}</strong>
                </span>
                <span className="checkpoint-language">
                  {languageNames(model).length <= 3
                    ? languageNames(model).join(", ")
                    : `${languageNames(model).length} languages`}
                </span>
                <span className={`checkpoint-state ${inUse ? "in-use" : ""}`}>
                  {inUse ? "In use" : variants.some((v) => v.installed) ? "Installed" : ""}
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
            <div className="checkpoint-detail-heading">
              <ProviderLogo provider={checkpoint.provider} />
              <div>
                <span className="checkpoint-provider">{checkpoint.provider}</span>
                <h2>{checkpoint.name}</h2>
              </div>
            </div>
            <div className="model-languages">
              <h3>Languages</h3>
              {languageNames(checkpoint).length <= 6 ? (
                <div className="language-chips">
                  {languageNames(checkpoint).map((name) => <span key={name}>{name}</span>)}
                </div>
              ) : (
                <p>{languageNames(checkpoint).join(", ")}</p>
              )}
            </div>
            <section className="model-versions" aria-label="Available versions">
              <h3>Versions</h3>
              {visible.map((model) => {
                const transferring = state.downloadModelID === model.id;
                const using = model.id === active?.id && state.ready;
                return (
                  <div
                    className={`variant ${using ? "variant-active" : ""}`}
                    key={model.id}
                  >
                    <div className="variant-row">
                      <div className="variant-heading">
                        <h4>{model.variant}</h4>
                        <p>
                          <span>{size(model.bytes)}</span>
                          {status(model, state) && (
                            <span className={`model-state ${using ? "in-use" : ""}`}>
                              {status(model, state)}
                            </span>
                          )}
                        </p>
                      </div>
                      <div className="model-actions">
                        {transferring ? (
                          <button
                            className="secondary"
                            onClick={() => void window.textify.action("cancel-download")}
                          >
                            Pause
                          </button>
                        ) : model.status !== "revoked" && !using ? (
                          <button
                            disabled={model.installed ? locked : installLocked}
                            onClick={() =>
                              void run({
                                action: model.installed
                                  ? model.status === "verify-required" ? "verify" : "use"
                                  : "download",
                                id: model.id,
                              })
                            }
                          >
                            {model.installed
                              ? model.status === "verify-required" ? "Verify" : "Use model"
                              : model.resumable ? "Resume" : "Download"}
                          </button>
                        ) : null}
                        {!transferring && (model.status !== "revoked" || model.storedBytes > 0) && (
                          <button
                            className="variant-more"
                            aria-label={`Options for ${model.variant}`}
                            aria-expanded={expandedVersion === model.id}
                            aria-controls={`options-${model.id}`}
                            onClick={() => expandVersion(expandedVersion === model.id ? null : model.id)}
                          >
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                              <circle cx="5" cy="12" r="1.8" />
                              <circle cx="12" cy="12" r="1.8" />
                              <circle cx="19" cy="12" r="1.8" />
                            </svg>
                          </button>
                        )}
                      </div>
                    </div>
                    {transferring && state.download !== null && (
                      <div className="download" role="status">
                        <progress value={state.download} max={1} aria-label={`Downloading ${model.variant}`} />
                        <span>{Math.round(state.download * 100)}%</span>
                      </div>
                    )}
                    {expandedVersion === model.id && !transferring && (
                      <div className="variant-options" id={`options-${model.id}`} role="group" aria-label={`Actions for ${model.variant}`}>
                        {model.status !== "revoked" && (
                          <button
                            className="secondary"
                            disabled={model.id === active?.id ? locked : installLocked}
                            onClick={() => void run({ action: "import", id: model.id })}
                          >
                            Import {model.directory ? "folder" : "file"}
                          </button>
                        )}
                        {model.storedBytes > 0 && (
                          <button
                            className="text-button"
                            disabled={locked}
                            onClick={() => void run({ action: "remove", id: model.id })}
                          >
                            Remove
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </section>
            <footer className="model-source">
              <h3>Source</h3>
              <a
                href={checkpoint.source}
                aria-label={`Open ${checkpoint.name} model page`}
                onClick={(event) => {
                  event.preventDefault();
                  void run({ action: "source", id: checkpoint.id });
                }}
              >
                <span>{checkpoint.source.replace(/^https:\/\//, "")}</span>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true">
                  <path d="M14 4h6v6m0-6L10 14M10 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-5" />
                </svg>
              </a>
            </footer>
          </section>
        )}
      </div>
    </div>
  );
}
