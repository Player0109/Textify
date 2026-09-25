import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { Preferences } from "../shared";

type Placement = Preferences["overlay"];
const initial: Placement = { x: 0, y: 0, scale: 1 };
const same = (a: Placement, b: Placement) =>
  a.x === b.x && a.y === b.y && a.scale === b.scale;
const signed = (value: number) => (value > 0 ? `+${value}` : String(value));

function Control({
  axis,
  title,
  detail,
  value,
  min,
  max,
  step,
  lower,
  upper,
  unit,
  disabled,
  change,
  commit,
}: {
  axis: keyof Placement;
  title: string;
  detail: string;
  value: number;
  min: number;
  max: number;
  step: number;
  lower: string;
  upper: string;
  unit: string;
  disabled: boolean;
  change(value: number): void;
  commit(): void;
}) {
  const [text, setText] = useState(String(value));
  useEffect(() => setText(String(value)), [value]);
  const normalize = (number: number) =>
    Math.min(
      max,
      Math.max(min, min + Math.round((number - min) / step) * step),
    );
  const finish = () => {
    const next =
      text.trim() && Number.isFinite(Number(text))
        ? normalize(Number(text))
        : value;
    setText(String(next));
    change(next);
    commit();
  };
  return (
    <div className="floating-control">
      <div className="floating-control-heading">
        <span className="floating-axis" aria-hidden="true">
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path
              d={
                axis === "x"
                  ? "M4 12h16m-5-5 5 5-5 5M9 7l-5 5 5 5"
                  : axis === "y"
                    ? "M12 4v16m-5-5 5 5 5-5M7 9l5-5 5 5"
                    : "M4 4l16 16M4 10V4h6m4 16h6v-6"
              }
            />
          </svg>
        </span>
        <div>
          <h3>{title}</h3>
          <p>{detail}</p>
        </div>
        <div className="floating-number">
          <label className="floating-value">
            <input
              aria-label={`Adjust ${title}`}
              type="number"
              min={min}
              max={max}
              step={step}
              disabled={disabled}
              value={text}
              onChange={(event) => {
                setText(event.target.value);
                const next = event.target.valueAsNumber;
                if (Number.isFinite(next) && next >= min && next <= max)
                  change(normalize(next));
              }}
              onBlur={finish}
              onKeyDown={(event) => {
                if (event.key === "Enter") event.currentTarget.blur();
              }}
            />
            <span aria-hidden="true">{unit}</span>
          </label>
          <div className="floating-stepper">
            {[1, -1].map((direction) => (
              <button
                key={direction}
                type="button"
                aria-label={`${direction > 0 ? "Increase" : "Decrease"} ${title}`}
                disabled={
                  disabled || (direction > 0 ? value >= max : value <= min)
                }
                onClick={() => {
                  change(normalize(value + direction * step));
                  commit();
                }}
              >
                <svg
                  aria-hidden="true"
                  width="12"
                  height="8"
                  viewBox="0 0 12 8"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.6"
                >
                  <path d={direction > 0 ? "m2 6 4-4 4 4" : "m2 2 4 4 4-4"} />
                </svg>
              </button>
            ))}
          </div>
        </div>
      </div>
      <input
        className="floating-slider"
        type="range"
        aria-label={title}
        aria-valuetext={`${value}${unit === "%" ? " percent" : " points"}`}
        min={min}
        max={max}
        step={step}
        value={value}
        disabled={disabled}
        style={
          {
            "--fill": `${((value - min) / (max - min)) * 100}%`,
          } as React.CSSProperties
        }
        onChange={(event) => change(Number(event.target.value))}
        onPointerUp={commit}
        onKeyUp={commit}
        onBlur={commit}
      />
      <div className="floating-limits" aria-hidden="true">
        <span>{lower}</span>
        <span>{upper}</span>
      </div>
    </div>
  );
}

function PositionPreview({ value }: { value: Placement }) {
  const host = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 500, height: 152 });
  useLayoutEffect(() => {
    setSize({
      width: host.current!.clientWidth,
      height: host.current!.clientHeight,
    });
    const observer = new ResizeObserver(([entry]) =>
      setSize({
        width: entry.contentRect.width,
        height: entry.contentRect.height,
      }),
    );
    observer.observe(host.current!);
    return () => observer.disconnect();
  }, []);
  const width = 104 * value.scale,
    height = 28 * value.scale;
  const x =
    size.width / 2 +
    (value.x / 2000) * Math.max(0, (size.width - width) / 2 - 14);
  const baseY = size.height - height / 2 - 13;
  const travel = value.y >= 0 ? Math.max(0, baseY - height / 2 - 34) : 9;
  const y = baseY - (value.y / 2000) * travel;
  return (
    <div
      className="floating-preview"
      ref={host}
      role="img"
      aria-label={`Floating icon preview: X ${signed(value.x)} points, Y ${signed(value.y)} points, scale ${Math.round(value.scale * 100)} percent`}
    >
      <div className="floating-preview-heading">
        <span>
          <svg
            aria-hidden="true"
            width="15"
            height="15"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.7"
          >
            <rect x="3" y="3" width="18" height="13" rx="1.5" />
            <path d="M9 21h6m-3-5v5" />
          </svg>{" "}
          Live Preview
        </span>
        <output>
          X {signed(value.x)} <b>•</b> Y {signed(value.y)} <b>•</b>{" "}
          {Math.round(value.scale * 100)}%
        </output>
      </div>
      <div className="floating-guide vertical" />
      <div className="floating-guide horizontal" />
      <div
        className="floating-mini"
        style={{
          left: x,
          top: y,
          transform: `translate(-50%, -50%) scale(${value.scale})`,
        }}
        aria-hidden="true"
      >
        <i className="floating-mini-dot" />
        <span className="floating-mini-voice">
          {[4, 8, 12, 7, 4].map((height, index) => (
            <i key={index} style={{ height }} />
          ))}
        </span>
        <strong>Textify</strong>
      </div>
    </div>
  );
}

export function FloatingIconSettings({
  preferences,
  busy,
  save,
}: {
  preferences: Preferences;
  busy: boolean;
  save(value: Preferences): Promise<boolean>;
}) {
  const [value, setValue] = useState(preferences.overlay);
  const draft = useRef(value);
  const saving = useRef(false);
  useEffect(() => {
    draft.current = preferences.overlay;
    setValue(preferences.overlay);
  }, [preferences.overlay.x, preferences.overlay.y, preferences.overlay.scale]);
  const change = (next: Placement) => {
    draft.current = next;
    setValue(next);
  };
  const commit = () => {
    if (saving.current || same(draft.current, preferences.overlay)) return;
    saving.current = true;
    void save({ ...preferences, overlay: draft.current })
      .then((saved) => {
        if (!saved) change(preferences.overlay);
      })
      .finally(() => {
        saving.current = false;
      });
  };
  return (
    <section className="floating-settings" aria-labelledby="floating-title">
      <h2 id="floating-title">Floating Icon</h2>
      <div className="floating-settings-card">
        <div className="floating-intro">
          <div>
            <h3>Place the indicator where it stays out of your way.</h3>
            <p>Offsets start at the active display’s bottom center.</p>
          </div>
          <button
            className="floating-reset"
            disabled={busy || same(value, initial)}
            onClick={() => {
              change(initial);
              commit();
            }}
          >
            <svg
              aria-hidden="true"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M5 8a8 8 0 1 1-1 7M5 3v5h5" />
            </svg>
            Reset Position &amp; Scale
          </button>
        </div>
        <div className="floating-settings-body">
          <PositionPreview value={value} />
          <div className="floating-controls">
            <Control
              axis="x"
              title="X Offset"
              detail="Left / Right"
              value={value.x}
              min={-2000}
              max={2000}
              step={1}
              lower="Left"
              upper="Right"
              unit="pt"
              disabled={busy}
              change={(x) => change({ ...draft.current, x })}
              commit={commit}
            />
            <Control
              axis="y"
              title="Y Offset"
              detail="Down / Up"
              value={value.y}
              min={-2000}
              max={2000}
              step={1}
              lower="Down"
              upper="Up"
              unit="pt"
              disabled={busy}
              change={(y) => change({ ...draft.current, y })}
              commit={commit}
            />
            <Control
              axis="scale"
              title="Scale"
              detail="Indicator size"
              value={Math.round(value.scale * 100)}
              min={50}
              max={200}
              step={5}
              lower="50%"
              upper="200%"
              unit="%"
              disabled={busy}
              change={(scale) => change({ ...draft.current, scale: scale / 100 })}
              commit={commit}
            />
          </div>
        </div>
      </div>
    </section>
  );
}
