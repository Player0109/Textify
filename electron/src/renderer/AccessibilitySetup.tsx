import React from "react";
import type { Action, Snapshot } from "../shared";
import textifyIcon from "../../assets/textify-icon.png";

export function AccessibilitySetup({ state, busy, run }: {
  state: Snapshot;
  busy: boolean;
  run: (action: Action) => Promise<void>;
}) {
  const permission = state.accessibility;
  if (!permission) return null;
  const granted = permission.status === "granted";
  const waiting = permission.status === "waiting";
  return (
    <section className={`accessibility-setup ${granted ? "granted" : ""}`} aria-label="Accessibility setup">
      <div className="accessibility-heading">
        <img src={textifyIcon} alt="" width="44" height="44" />
        <div>
          <h2>Accessibility</h2>
          <p>Use your dictation shortcut and paste into the app you’re writing in.</p>
        </div>
        <span className={`permission-status ${permission.status}`} role="status">
          <span aria-hidden="true">{granted ? "✓" : "●"}</span>
          {granted ? "Enabled" : waiting ? "Waiting for permission" : "Setup needed"}
        </span>
      </div>
      {granted ? (
        <p className="permission-success">
          {state.triggerEnabled ? `You're ready. ${state.triggerStatus} to dictate.` : "Access is enabled. Your global shortcut can now be activated."}
        </p>
      ) : (
        <>
          <ol className="permission-steps">
            <li>Open Accessibility settings using the button below.</li>
            <li>If <strong>{permission.appName}</strong> is missing, drag it from the floating helper into the list. Then turn on its switch.</li>
          </ol>
          <div className="permission-action">
            <button disabled={busy} onClick={() => void run(waiting ? "permission-settings" : "permissions")}>
              {waiting ? "Open Settings" : "Enable Accessibility"}
            </button>
            <p>Textify detects approval and activates your shortcut automatically.</p>
          </div>
          <details className="permission-help">
            <summary>App missing, or already switched on?</summary>
            <p>You can also click <strong>+</strong> in Accessibility settings, choose this app, then click <strong>Open</strong>.</p>
            <code>{permission.appPath}</code>
            <button className="secondary" disabled={busy} onClick={() => void run("reveal-app")}>
              Show {permission.appName} in Finder
            </button>
            <p>If the switch is already on but access isn’t detected, quit Textify, remove its old entry with <strong>−</strong>, and add this copy again.</p>
          </details>
        </>
      )}
    </section>
  );
}
