import React, { useEffect, useLayoutEffect, useRef } from "react";
import type { Snapshot } from "../shared";
import textifyIcon from "../../assets/textify-icon.png";

function SignalWaveform({ recording }: { recording: boolean }) {
  const waveform = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const bars = Array.from(waveform.current!.children) as HTMLElement[];
    let frame = 0;
    let last = -Infinity;
    const draw = (now: number) => {
      if (now - last >= 1000 / 30) {
        last = now;
        const time = (now / 1000) * (recording ? 3.9 : 5.4);
        bars.forEach((bar, index) => {
          const position = index / (bars.length - 1);
          const carrier = (Math.sin(time + position * 13.5) + 1) * 0.5;
          const detail = (Math.sin(time * 0.63 - position * 27) + 1) * 0.5;
          const center = (Math.sin(time * 0.28) + 1) * 0.5;
          const energy = Math.exp(-((position - center) ** 2) / 0.032);
          // Match the native RecordingSignalWaveform's continuous motion.
          // Audio-level snapshots must not restart the animation or jump bars.
          const height = 0.16 + carrier * 0.34 + detail * 0.18 + energy * 0.32;
          bar.style.height = `${Math.max(3, 11 * Math.min(1, height))}px`;
        });
      }
      frame = requestAnimationFrame(draw);
    };
    draw(performance.now());
    return () => cancelAnimationFrame(frame);
  }, [recording]);
  return (
    <span className="overlay-waveform" ref={waveform} aria-hidden="true">
      {Array.from({ length: 34 }, (_, index) => (
        <i key={index} style={{ opacity: 0.36 + (index / 33) * 0.32 }} />
      ))}
    </span>
  );
}

function LiveTranscript({ text }: { text: string }) {
  const viewport = useRef<HTMLDivElement>(null);
  const transcript = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const content = transcript.current!;
    const frame = viewport.current!;
    const alignNewestLine = () => {
      const offset = Math.max(0, content.offsetHeight - frame.clientHeight);
      content.style.transform = `translateY(${-offset}px)`;
    };
    alignNewestLine();
    const observer = new ResizeObserver(alignNewestLine);
    observer.observe(content);
    observer.observe(frame);
    return () => observer.disconnect();
  }, []);
  return (
    <div
      className="overlay-transcript"
      ref={viewport}
      aria-live="polite"
      aria-label="Live transcript"
    >
      <div className="overlay-transcript-content" ref={transcript}>
        {text}
      </div>
    </div>
  );
}

export function Overlay({ state }: { state: Snapshot }) {
  const recording = state.phase === "recording";
  const copy = state.phase === "copy";
  const error = state.phase === "error";
  const active = recording || ["processing", "inserting"].includes(state.phase);
  return (
    <div
      className={`overlay studio-overlay ${state.phase}${state.preview || error ? " expanded" : ""}`}
      aria-label={`Textify floating bar${recording ? " · Listening · Escape to cancel" : ""}`}
    >
      <div className="overlay-identity">
        <span className="overlay-app-icon" aria-hidden="true">
          {state.applicationIcon ? (
            <img src={state.applicationIcon} alt="" />
          ) : state.application === "Textify" ? (
            <img src={textifyIcon} alt="" />
          ) : (
            <svg
              width="15"
              height="15"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.4"
            >
              <rect x="2" y="4" width="20" height="16" rx="3" />
              <path d="M2 9h20M6 6.5h.1m3 0h.1" />
            </svg>
          )}
        </span>
        <strong className="overlay-app-name">
          {state.application || "Textify"}
        </strong>
        <span className="overlay-wordmark" aria-hidden="true">
          <span className="overlay-voice-mark">
            {[5.3, 9.5, 14, 8.1, 4.5].map((height, i) => (
              <i key={i} style={{ height, animationDelay: `${i * -0.15}s` }} />
            ))}
          </span>
          Textify
        </span>
      </div>
      <div className="overlay-signal">
        {active ? (
          <SignalWaveform recording={recording} />
        ) : (
          <span className="overlay-status">
            <i />
            {copy ? "Ready to copy" : error ? "Dictation stopped" : "Ready"}
          </span>
        )}
        {copy && (
          <button
            className="overlay-copy"
            onClick={() => void window.textify.action("copy")}
          >
            Copy
          </button>
        )}
        {(copy || error) && (
          <button
            className="overlay-dismiss"
            aria-label="Dismiss"
            onClick={() => void window.textify.action("dismiss")}
          >
            <svg
              width="10"
              height="10"
              viewBox="0 0 12 12"
              stroke="currentColor"
              strokeWidth="1.5"
              aria-hidden="true"
            >
              <path d="m2 2 8 8m0-8-8 8" />
            </svg>
          </button>
        )}
      </div>
      {error ? (
        <div className="overlay-error" role="alert">
          {state.message}
        </div>
      ) : state.preview ? (
        <LiveTranscript text={state.preview} />
      ) : null}
    </div>
  );
}
