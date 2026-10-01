import type { UpdateView } from "../shared";

// The part of electron-updater's AppUpdater that Textify uses.
export interface Updater {
  autoDownload: boolean;
  autoInstallOnAppQuit: boolean;
  checkForUpdates(): Promise<unknown>;
  downloadUpdate(): Promise<unknown>;
  on(event: "update-available", listener: (info: { version: string }) => void): unknown;
  on(event: "update-not-available", listener: () => void): unknown;
  on(event: "download-progress", listener: (progress: { percent: number }) => void): unknown;
  on(event: "error", listener: (error: Error) => void): unknown;
}

// The source of the update-downloaded event. On macOS this is Electron's
// autoUpdater, which runs Squirrel.Mac. On Windows and Linux it is the
// electron-updater instance itself.
export interface NativeUpdater {
  on(event: "update-downloaded", listener: () => void): unknown;
}

const CHECK_INTERVAL = 6 * 60 * 60 * 1000;

export class Updates {
  view: UpdateView | null = null;
  private timer: ReturnType<typeof setInterval> | undefined;
  private announced = "";

  constructor(
    private readonly updater: Updater,
    native: NativeUpdater,
    private readonly changed: () => void,
    private readonly announce: (version: string) => void,
  ) {
    // Downloads start only when the user chooses Update. A downloaded update
    // installs the next time Textify quits, without another prompt.
    updater.autoDownload = false;
    updater.autoInstallOnAppQuit = true;
    updater.on("update-available", ({ version }) => {
      if (this.busy) return;
      this.set({ status: "available", version, progress: 0 });
      if (version !== this.announced) {
        this.announced = version;
        this.announce(version);
      }
    });
    updater.on("update-not-available", () => {
      if (!this.busy) this.set(null);
    });
    // On macOS electron-updater finishes when it hands the ZIP to Squirrel.Mac.
    // The update is ready only after Squirrel.Mac has staged it for
    // installation. On Windows the event follows the publisher check.
    native.on("update-downloaded", () => {
      if (this.view?.status === "downloading")
        this.set({ ...this.view, status: "ready", progress: 1 });
    });
    updater.on("download-progress", ({ percent }) => {
      if (this.view?.status === "downloading")
        this.set({ ...this.view, progress: percent / 100 });
    });
    // Failed background checks stay quiet. Only an update the user asked for
    // reports a failure, including one macOS rejects after the download.
    updater.on("error", () => {
      if (this.view && this.busy) this.set({ ...this.view, status: "failed" });
    });
  }

  private get busy() {
    return this.view?.status === "downloading" || this.view?.status === "ready";
  }

  private set(view: UpdateView | null) {
    this.view = view;
    this.changed();
  }

  setEnabled(enabled: boolean) {
    this.stop();
    if (!enabled) return;
    this.check();
    this.timer = setInterval(() => this.check(), CHECK_INTERVAL);
  }

  stop() {
    clearInterval(this.timer);
    this.timer = undefined;
  }

  private check() {
    if (!this.busy) void this.updater.checkForUpdates().catch(() => {});
  }

  async download() {
    const view = this.view;
    if (view?.status !== "available" && view?.status !== "failed") return;
    this.set({ ...view, status: "downloading", progress: 0 });
    try {
      await this.updater.downloadUpdate();
      if (this.view?.status === "downloading")
        this.set({ ...this.view, progress: 1 });
    } catch {
      if (this.view) this.set({ ...this.view, status: "failed" });
    }
  }
}
