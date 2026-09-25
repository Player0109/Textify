import { spawn } from "node:child_process";
import { join } from "node:path";
import type { Target } from "../core/dictation";
import type { Trigger } from "../shared";

export function nativeRequest(
  binary: string,
  args: string[],
  input = "",
): Promise<any> {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, {
      stdio: "pipe",
      shell: false,
      windowsHide: true,
    });
    let output = "";
    let settled = false;
    const finish = (error?: Error, value?: any) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    };
    const timer = setTimeout(() => {
      child.kill();
      finish(new Error("native_timeout"));
    }, 5000);
    child.stdout.on("data", (data) => {
      output += data;
      if (output.length > (args[0] === "apps" ? 262144 : 16384)) {
        child.kill();
        finish(new Error("native_protocol"));
      }
    });
    child.stderr.resume();
    child.on("error", () => finish(new Error("native_unavailable")));
    child.stdin.on("error", () => {});
    child.on("close", (code) => {
      try {
        if (code !== 0) throw new Error();
        finish(undefined, JSON.parse(output));
      } catch {
        finish(new Error("native_protocol"));
      }
    });
    child.stdin.end(input);
  });
}
export class Platform {
  readonly insertion = process.platform === "linux" ? "copy" : "automatic";
  readonly exclusionsAvailable = !(
    process.platform === "linux" &&
    Boolean(
      process.env.WAYLAND_DISPLAY || process.env.XDG_SESSION_TYPE === "wayland",
    )
  );
  private binary: string;
  constructor(resources: string) {
    this.binary = join(
      resources,
      `textify-platform${process.platform === "win32" ? ".exe" : ""}`,
    );
  }
  async target(): Promise<Target | null> {
    if (!this.exclusionsAvailable) return null;
    const result = await nativeRequest(this.binary, ["target"]);
    if (
      typeof result.target !== "string" ||
      !/^[0-9:]+$/.test(result.target) ||
      typeof result.secure !== "boolean"
    )
      throw new Error("native_protocol");
    return result;
  }
  async apps(): Promise<{ id: string; name: string }[]> {
    if (!this.exclusionsAvailable) return [];
    const result = await nativeRequest(this.binary, ["apps"]);
    if (
      !Array.isArray(result) ||
      result.length > 200 ||
      result.some(
        (entry) =>
          typeof entry?.id !== "string" ||
          typeof entry?.name !== "string" ||
          entry.id.length > 4096 ||
          entry.name.length > 256,
      )
    )
      throw new Error("native_protocol");
    return result;
  }
  async insert(
    text: string,
    target: Target,
  ): Promise<"sent" | "skipped" | "unavailable"> {
    if (this.insertion === "copy") return "unavailable";
    try {
      const result = await nativeRequest(
        this.binary,
        ["paste", target.target],
        text,
      );
      if (!["sent", "skipped", "unavailable"].includes(result.status))
        return "skipped";
      return result.status;
    } catch {
      // A crashed/timed-out helper may already have sent paste. Never offer a retry.
      return "skipped";
    }
  }
}

export interface TriggerEvents {
  press(): void;
  release(): void;
  cancel(): void;
  other(modifier: boolean): void;
}
export async function nativeTrigger(
  trigger: Trigger,
  events: TriggerEvents,
): Promise<() => void> {
  const { uIOhook, UiohookKey: key } = await import("uiohook-napi");
  let held = false;
  const modifiers = new Set<number>([
    key.Ctrl,
    key.CtrlRight,
    key.Alt,
    key.AltRight,
    key.Shift,
    key.ShiftRight,
    key.Meta,
    key.MetaRight,
  ]);
  const matches = (e: { keycode: number; ctrlKey: boolean }) =>
    trigger === "control-space"
      ? e.keycode === key.Space && e.ctrlKey
      : e.keycode ===
        (trigger === "right-command"
          ? key.MetaRight
          : trigger === "right-option"
            ? key.AltRight
            : key.CtrlRight);
  const down = (e: { keycode: number; ctrlKey: boolean }) => {
    if (e.keycode === key.Escape) {
      events.cancel();
      return;
    }
    if (matches(e)) {
      if (!held) {
        held = true;
        events.press();
      }
    } else events.other(modifiers.has(e.keycode));
  };
  const up = (e: { keycode: number; ctrlKey: boolean }) => {
    if (
      held &&
      (matches(e) ||
        (trigger === "control-space" &&
          new Set<number>([key.Space, key.Ctrl, key.CtrlRight]).has(e.keycode)))
    ) {
      held = false;
      events.release();
    }
  };
  uIOhook.on("keydown", down);
  uIOhook.on("keyup", up);
  uIOhook.start();
  return () => {
    uIOhook.off("keydown", down);
    uIOhook.off("keyup", up);
    uIOhook.stop();
  };
}
