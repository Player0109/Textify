import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AccessibilitySetup } from "../src/main/accessibility";

describe("guided Accessibility setup", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  function setup(initial = false) {
    let granted = initial;
    const trusted = vi.fn((_prompt: boolean) => granted);
    const changed = vi.fn();
    const permission = new AccessibilitySetup(trusted, changed);
    return { permission, trusted, changed, grant: (value: boolean) => { granted = value; } };
  }
  it("checks existing approval without prompting", () => {
    const { permission, trusted, changed } = setup(true);
    permission.refresh();
    permission.request();
    expect(permission.status).toBe("granted");
    expect(trusted.mock.calls.every(([prompt]) => !prompt)).toBe(true);
    expect(changed).toHaveBeenCalledExactlyOnceWith(true);
    expect(vi.getTimerCount()).toBe(0);
  });
  it("waits for asynchronous approval and notifies shortcut activation once", () => {
    const { permission, trusted, changed, grant } = setup();
    permission.request();
    expect(permission.status).toBe("waiting");
    expect(trusted.mock.calls.filter(([prompt]) => prompt)).toHaveLength(1);
    vi.advanceTimersByTime(2000);
    expect(changed).not.toHaveBeenCalledWith(true);
    grant(true);
    vi.advanceTimersByTime(1000);
    expect(permission.status).toBe("granted");
    expect(changed.mock.calls.filter(([value]) => value)).toHaveLength(1);
    permission.refresh();
    expect(changed.mock.calls.filter(([value]) => value)).toHaveLength(1);
    expect(vi.getTimerCount()).toBe(0);
  });
  it("does not repeat the native prompt when reopening settings", () => {
    const { permission, trusted } = setup();
    permission.request();
    permission.request(false);
    permission.request();
    expect(trusted.mock.calls.filter(([prompt]) => prompt)).toHaveLength(1);
    expect(vi.getTimerCount()).toBe(1);
  });
  it("bounds polling and detects a later grant on returning to Textify", () => {
    const { permission, grant, trusted } = setup();
    permission.request();
    vi.advanceTimersByTime(5 * 60_000);
    expect(permission.status).toBe("required");
    expect(vi.getTimerCount()).toBe(0);
    grant(true);
    permission.refresh();
    expect(permission.status).toBe("granted");
    expect(trusted.mock.calls.filter(([prompt]) => prompt)).toHaveLength(1);
  });
  it("reports revocation and stops polling on shutdown", () => {
    const { permission, grant, changed } = setup(true);
    permission.refresh();
    grant(false);
    permission.refresh();
    expect(permission.status).toBe("required");
    expect(changed).toHaveBeenLastCalledWith(false);
    permission.request(false);
    permission.stop();
    expect(vi.getTimerCount()).toBe(0);
  });
});
