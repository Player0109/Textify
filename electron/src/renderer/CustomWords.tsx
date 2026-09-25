import React, { useState } from "react";
import type { Preferences } from "../shared";
export function CustomWords({
  preferences,
  busy,
  save,
}: {
  preferences: Preferences;
  busy: boolean;
  save(value: Preferences): Promise<boolean>;
}) {
  const [word, setWord] = useState("");
  return (
    <section className="vocabulary vocabulary-panel custom-words">
      <h2>Custom words</h2>
      <p>
        Give Whisper names or terms to listen for. Recognition is not
        guaranteed.
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (word.trim())
            void save({
              ...preferences,
              customWords: [...preferences.customWords, word],
            }).then((saved) => {
              if (saved) setWord("");
            });
        }}
      >
        <label>
          Word or phrase
          <input
            aria-label="Custom word"
            maxLength={80}
            value={word}
            onChange={(event) => setWord(event.target.value)}
            required
            placeholder="A name or specialist term"
          />
        </label>
        <button disabled={busy || preferences.customWords.length >= 100}>
          Add word
        </button>
      </form>
      <ul>
        {preferences.customWords.map((value, index) => (
          <li key={value}>
            <span>{value}</span>
            <button
              className="text-button"
              disabled={busy}
              onClick={() =>
                void save({
                  ...preferences,
                  customWords: preferences.customWords.filter(
                    (_, i) => i !== index,
                  ),
                })
              }
            >
              Remove word
            </button>
          </li>
        ))}
      </ul>
      {!preferences.customWords.length && (
        <div className="vocabulary-empty">No custom words yet</div>
      )}
    </section>
  );
}
