import React from "react";
import textifyIcon from "../../assets/textify-icon.png";

export function AccessibilityDragHelp() {
  return (
    <div className="accessibility-drag-help" role="dialog" aria-label="Add Textify to Accessibility">
      <div className="accessibility-drag-header">
        <strong>Add Textify to Accessibility</strong>
        <button aria-label="Close helper" onClick={() => window.textify.accessibilityHelp("dismiss")}>×</button>
      </div>
      <p>Missing from the list? Drag this icon into it.</p>
      <div className="accessibility-drag-row">
        <div
          className="accessibility-drag-source"
          role="button"
          tabIndex={0}
          draggable
          aria-label="Drag Textify into the Accessibility list"
          onDragStart={(event) => {
            event.preventDefault();
            window.textify.accessibilityHelp("drag");
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              window.textify.accessibilityHelp("reveal");
            }
          }}
        >
          <img src={textifyIcon} alt="" />
          <span>Textify</span>
          <span aria-hidden="true">↗</span>
        </div>
      </div>
      <p className="accessibility-drag-footnote">Then turn on the Textify switch.</p>
    </div>
  );
}
