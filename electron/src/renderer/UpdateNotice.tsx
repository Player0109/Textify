import React from "react";
import type { UpdateView } from "../shared";

export function UpdateNotice({ update }: { update: UpdateView | null }) {
  if (!update) return null;
  const text =
    update.status === "available"
      ? `Textify ${update.version} is available.`
      : update.status === "downloading"
        ? update.progress < 1
          ? `Downloading Textify ${update.version}… ${Math.round(update.progress * 100)}%`
          : `Preparing Textify ${update.version}…`
        : update.status === "ready"
          ? `Textify ${update.version} is ready. It installs the next time you quit Textify.`
          : "The update could not be installed. Check your connection and try again.";
  const button =
    update.status === "available"
      ? "Update"
      : update.status === "failed"
        ? "Try again"
        : "";
  return (
    <div className="notice update-notice" role="status">
      <span>{text}</span>
      {button && (
        <button onClick={() => void window.textify.action("update")}>
          {button}
        </button>
      )}
    </div>
  );
}
