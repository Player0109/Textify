import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Updates, type Updater } from "../src/main/updates";

const SIX_HOURS = 6 * 60 * 60 * 1000;

class FakeUpdater extends EventEmitter {
  autoDownload = true;
  autoInstallOnAppQuit = false;
  checkForUpdates = vi.fn(async () => undefined);
  downloadUpdate = vi.fn(async () => undefined);
}

function setup() {
  const updater = new FakeUpdater();
  // Electron's native autoUpdater, which Squirrel.Mac drives.
  const squirrel = new EventEmitter();
  const changed = vi.fn();
  const announce = vi.fn();
  const updates = new Updates(updater as unknown as Updater, squirrel, changed, announce);
  return { updater, squirrel, changed, announce, updates };
}
async function downloadAndStage(updater: FakeUpdater, squirrel: EventEmitter, updates: Updates) {
  await updates.download();
  squirrel.emit("update-downloaded");
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("app updates", () => {
  it("waits for the user before downloading and installs a downloaded update on quit", () => {
    const { updater } = setup();
    expect(updater.autoDownload).toBe(false);
    expect(updater.autoInstallOnAppQuit).toBe(true);
  });

  it("checks when enabled and every six hours until turned off", async () => {
    const { updater, updates } = setup();
    updates.setEnabled(true);
    expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(SIX_HOURS);
    expect(updater.checkForUpdates).toHaveBeenCalledTimes(2);
    updates.setEnabled(false);
    await vi.advanceTimersByTimeAsync(SIX_HOURS * 2);
    expect(updater.checkForUpdates).toHaveBeenCalledTimes(2);
  });

  it("stops scheduled checks when Textify quits", async () => {
    const { updater, updates } = setup();
    updates.setEnabled(true);
    updates.stop();
    await vi.advanceTimersByTimeAsync(SIX_HOURS);
    expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
  });

  it("announces each new version once and does not download it automatically", () => {
    const { updater, updates, announce, changed } = setup();
    updater.emit("update-available", { version: "0.2.0-preview.24" });
    updater.emit("update-available", { version: "0.2.0-preview.24" });
    expect(updates.view).toEqual({
      status: "available",
      version: "0.2.0-preview.24",
      progress: 0,
    });
    expect(announce).toHaveBeenCalledTimes(1);
    expect(announce).toHaveBeenCalledWith("0.2.0-preview.24");
    expect(changed).toHaveBeenCalled();
    updater.emit("update-available", { version: "0.2.0-preview.25" });
    expect(announce).toHaveBeenLastCalledWith("0.2.0-preview.25");
    expect(updater.downloadUpdate).not.toHaveBeenCalled();
  });

  it("downloads after the user chooses Update and is ready only once macOS staged it", async () => {
    const { updater, squirrel, updates } = setup();
    let finish!: () => void;
    updater.downloadUpdate.mockReturnValue(
      new Promise<undefined>((resolve) => {
        finish = () => resolve(undefined);
      }),
    );
    updater.emit("update-available", { version: "1.0.0" });
    const download = updates.download();
    expect(updates.view).toEqual({ status: "downloading", version: "1.0.0", progress: 0 });
    updater.emit("download-progress", { percent: 40 });
    expect(updates.view?.progress).toBe(0.4);
    finish();
    await download;
    // Squirrel.Mac still unpacks and verifies the app; quitting now would lose it.
    expect(updates.view).toEqual({ status: "downloading", version: "1.0.0", progress: 1 });
    squirrel.emit("update-downloaded");
    expect(updates.view).toEqual({ status: "ready", version: "1.0.0", progress: 1 });
  });

  it("is ready once electron-updater reports a checked download on Windows and Linux", async () => {
    const updater = new FakeUpdater();
    const updates = new Updates(updater as unknown as Updater, updater, vi.fn(), vi.fn());
    // electron-updater emits update-downloaded before downloadUpdate resolves.
    updater.downloadUpdate.mockImplementation(async () => {
      updater.emit("update-downloaded");
      return undefined;
    });
    updater.emit("update-available", { version: "1.0.0" });
    await updates.download();
    expect(updates.view).toEqual({ status: "ready", version: "1.0.0", progress: 1 });
  });

  it("ignores a staged update the user did not start", () => {
    const { squirrel, updater, updates } = setup();
    updater.emit("update-available", { version: "1.0.0" });
    squirrel.emit("update-downloaded");
    expect(updates.view?.status).toBe("available");
  });

  it("does not check again or accept another download while one is in progress or ready", async () => {
    const { updater, squirrel, updates } = setup();
    updates.setEnabled(true);
    updater.emit("update-available", { version: "1.0.0" });
    await downloadAndStage(updater, squirrel, updates);
    await updates.download();
    expect(updater.downloadUpdate).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(SIX_HOURS);
    expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
    updater.emit("update-not-available");
    expect(updates.view?.status).toBe("ready");
  });

  it("ignores Update when no update is available", async () => {
    const { updater, updates } = setup();
    await updates.download();
    expect(updater.downloadUpdate).not.toHaveBeenCalled();
    expect(updates.view).toBeNull();
  });

  it("keeps background check failures quiet", async () => {
    const { updater, updates } = setup();
    updater.checkForUpdates.mockRejectedValue(new Error("offline"));
    updates.setEnabled(true);
    updater.emit("error", new Error("offline"));
    await vi.advanceTimersByTimeAsync(0);
    expect(updates.view).toBeNull();
  });

  it("clears an offer that is no longer published", () => {
    const { updater, updates } = setup();
    updater.emit("update-available", { version: "1.0.0" });
    updater.emit("update-not-available");
    expect(updates.view).toBeNull();
  });

  it("reports a failed download and lets the user try again", async () => {
    const { updater, squirrel, updates } = setup();
    updater.emit("update-available", { version: "1.0.0" });
    updater.downloadUpdate.mockImplementationOnce(async () => {
      updater.emit("error", new Error("network"));
      throw new Error("network");
    });
    await updates.download();
    expect(updates.view).toEqual({ status: "failed", version: "1.0.0", progress: 0 });
    await downloadAndStage(updater, squirrel, updates);
    expect(updates.view?.status).toBe("ready");
  });

  it("reports a failure that macOS raises while staging the download", async () => {
    const { updater, updates } = setup();
    updater.emit("update-available", { version: "1.0.0" });
    await updates.download();
    updater.emit("error", new Error("code signature"));
    expect(updates.view?.status).toBe("failed");
  });
});
