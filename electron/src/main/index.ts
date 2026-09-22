import {
  app,
  BrowserWindow,
  Menu,
  Tray,
  nativeImage,
  ipcMain,
  clipboard,
  session,
  dialog,
  screen,
  systemPreferences,
  shell,
} from "electron";
import type { IpcMainInvokeEvent, WebContents } from "electron";
import { readFile, writeFile, mkdir, rename } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { Dictation } from "../core/dictation";
import { Models } from "./models";
import { WhisperWorker } from "./worker";
import { Platform, nativeTrigger } from "./platform";
import { waylandTrigger } from "./wayland";
import { Capture } from "./capture";
import { validatePreferences } from "./preferences";
import type { Action, Preferences, Snapshot } from "../shared";

app.setName("Textify Electron");
const smoke = !app.isPackaged && process.argv.includes("--smoke");
app.setPath(
  "userData",
  smoke && process.env.TEXTIFY_ELECTRON_TEST_DATA
    ? process.env.TEXTIFY_ELECTRON_TEST_DATA
    : join(app.getPath("appData"), "Textify Electron"),
);
if (process.platform === "linux")
  app.setDesktopName("io.github.Player0109.Textify.Electron.desktop");
const resources = app.isPackaged
  ? join(process.resourcesPath, "textify")
  : join(__dirname, "../resources");
const page = join(__dirname, "renderer/index.html");
let main: BrowserWindow,
  audio: BrowserWindow,
  overlay: BrowserWindow,
  tray: Tray;
let quitting = false,
  cleaned = false,
  modelBusy = false,
  initialized = false;
let notice = "",
  triggerStatus = "Global trigger is off",
  stopTrigger: (() => void) | undefined;
let enabling = false,
  savingPreferences = false;
const wayland =
  process.platform === "linux" &&
  Boolean(
    process.env.WAYLAND_DISPLAY || process.env.XDG_SESSION_TYPE === "wayland",
  );
let preferences: Preferences = {
  microphone: "default",
  trigger:
    process.platform === "darwin"
      ? "right-command"
      : wayland
        ? "control-space"
        : "right-control",
  replacements: [],
};
const platform = new Platform(resources);
let models: Models,
  worker: WhisperWorker,
  capture: Capture,
  dictation: Dictation;
let broadcastTimer: ReturnType<typeof setTimeout> | undefined;
function snapshot(): Snapshot {
  return {
    phase: dictation?.phase ?? "idle",
    message: notice || dictation?.message || "",
    level: dictation?.level ?? 0,
    elapsed: dictation?.elapsed ?? 0,
    platform:
      process.platform === "darwin"
        ? "macOS"
        : process.platform === "win32"
          ? "Windows"
          : wayland
            ? "Linux · Wayland"
            : "Linux · X11",
    insertion: platform.insertion,
    triggerStatus,
    ready: Boolean(initialized && worker?.ready),
    modelBusy: modelBusy || Boolean(models?.busy),
    download: models?.progress ?? null,
    preferences,
    models: models?.file
      ? [
          {
            id: models.id,
            name: models.name,
            bytes: models.file.sizeBytes,
            installed: models.installed,
          },
        ]
      : [],
  };
}
function changed() {
  if (broadcastTimer || quitting) return;
  broadcastTimer = setTimeout(() => {
    broadcastTimer = undefined;
    const state = snapshot();
    for (const win of [main, overlay])
      if (win && !win.isDestroyed()) win.webContents.send("snapshot", state);
    if (!overlay || overlay.isDestroyed()) return;
    const visible = [
      "recording",
      "processing",
      "inserting",
      "copy",
      "error",
    ].includes(state.phase);
    if (visible) {
      const area = screen.getDisplayNearestPoint(
        screen.getCursorScreenPoint(),
      ).workArea;
      overlay.setPosition(
        Math.round(area.x + (area.width - 390) / 2),
        Math.round(area.y + area.height - 125),
      );
      overlay.setFocusable(state.phase === "copy" || state.phase === "error");
      if (!overlay.isVisible()) overlay.showInactive();
    } else overlay.hide();
  }, 50);
}
function showMain() {
  if (main && !main.isDestroyed()) {
    main.show();
    main.focus();
  }
}
function allowed(event: IpcMainInvokeEvent, windows: BrowserWindow[]) {
  return windows.some(
    (win) =>
      win &&
      !win.isDestroyed() &&
      event.sender === win.webContents &&
      event.senderFrame === win.webContents.mainFrame,
  );
}
function configure(win: BrowserWindow) {
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (event) => event.preventDefault());
  win.webContents.on("will-attach-webview", (event) => event.preventDefault());
}
function createWindow(options: Electron.BrowserWindowConstructorOptions) {
  const win = new BrowserWindow({
    ...options,
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false,
      spellcheck: false,
    },
  });
  configure(win);
  return win;
}
async function enableTrigger() {
  if (enabling) return;
  enabling = true;
  stopTrigger?.();
  stopTrigger = undefined;
  const events = {
    press: () => {
      if (worker.ready && !modelBusy && !models.busy) {
        notice = "";
        dictation.press(main?.isFocused() ?? false);
      } else {
        notice = "Install and load a model before dictating.";
        changed();
      }
    },
    release: () => {
      void dictation.release();
    },
    cancel: () => {
      if (["armed", "recording"].includes(dictation.phase))
        void dictation.cancel();
    },
    other: (modifier: boolean) => dictation.otherKey(modifier),
  };
  try {
    if (
      process.platform === "darwin" &&
      !systemPreferences.isTrustedAccessibilityClient(false)
    ) {
      triggerStatus =
        "Enable Accessibility permission, then enable the trigger.";
      return;
    }
    if (wayland) {
      const trigger = await waylandTrigger(events);
      stopTrigger = trigger.stop;
      triggerStatus = `Hold ${trigger.description}`;
    } else {
      stopTrigger = await nativeTrigger(preferences.trigger, events);
      triggerStatus = `Hold ${preferences.trigger === "right-command" ? "Right Command" : preferences.trigger === "right-control" ? "Right Control" : "Control + Space"}`;
    }
  } catch {
    triggerStatus =
      "Global trigger unavailable. Use the microphone button in Textify.";
  } finally {
    enabling = false;
    changed();
  }
}
async function loadModel() {
  modelBusy = true;
  changed();
  try {
    await worker.load(models.path);
    notice = "";
  } catch {
    notice =
      "The speech engine could not load. Reopen Textify or reinstall this preview.";
  } finally {
    modelBusy = false;
    changed();
  }
}
async function action(action: Action) {
  const active = dictation.busy;
  switch (action) {
    case "press":
      if (worker.ready && !modelBusy && !models.busy) {
        notice = "";
        dictation.press(true);
      }
      break;
    case "release":
      await dictation.release();
      break;
    case "cancel":
      if (["armed", "recording"].includes(dictation.phase))
        await dictation.cancel();
      break;
    case "copy":
      if (!active && dictation.pending) {
        clipboard.writeText(dictation.pending);
        dictation.dismiss();
      }
      break;
    case "dismiss":
      if (!active) {
        notice = "";
        dictation.dismiss();
      }
      break;
    case "microphone":
      if (!active) {
        await capture.probe();
        notice = "Microphone permission is available.";
      }
      break;
    case "permissions":
      if (process.platform === "darwin") {
        systemPreferences.isTrustedAccessibilityClient(true);
        await shell.openExternal(
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        );
      } else
        notice = "Use your system privacy settings to allow microphone access.";
      break;
    case "enable-trigger":
      if (!active) await enableTrigger();
      break;
    case "cancel-download":
      models.cancel();
      break;
    case "download":
    case "import": {
      if (active || modelBusy || models.busy || !initialized) return;
      let source: string | undefined;
      if (action === "import") {
        const chosen = await dialog.showOpenDialog(main, {
          title: "Choose the catalog Whisper small.en model",
          properties: ["openFile"],
          filters: [{ name: "Whisper model", extensions: ["bin"] }],
        });
        if (chosen.canceled) return;
        if (dictation.busy || modelBusy || models.busy) return;
        source = chosen.filePaths[0];
      }
      try {
        await models.install(source);
        await loadModel();
      } catch {
        notice =
          "Model installation stopped. Use the exact catalog model or retry the download.";
      }
      break;
    }
    default:
      throw new Error("unsupported_action");
  }
  changed();
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", showMain);
  app.on("activate", showMain);
  app
    .whenReady()
    .then(async () => {
      await mkdir(app.getPath("userData"), { recursive: true });
      try {
        preferences = validatePreferences(
          JSON.parse(
            await readFile(
              join(app.getPath("userData"), "settings.json"),
              "utf8",
            ),
          ),
        );
      } catch {
        /* Fresh install uses defaults. */
      }
      models = new Models(
        resources,
        join(app.getPath("userData"), "models"),
        changed,
      );
      worker = new WhisperWorker(
        join(
          resources,
          `textify-whisper${process.platform === "win32" ? ".exe" : ""}`,
        ),
        changed,
      );
      main = createWindow({
        width: 1000,
        height: 740,
        minWidth: 780,
        minHeight: 600,
        title: "Textify Electron",
        backgroundColor: "#f6f8fc",
        show: false,
      });
      audio = createWindow({ show: false, width: 1, height: 1 });
      overlay = createWindow({
        width: 390,
        height: 96,
        frame: false,
        transparent: true,
        alwaysOnTop: true,
        skipTaskbar: true,
        focusable: false,
        resizable: false,
        show: false,
      });
      overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      capture = new Capture(audio);
      dictation = new Dictation(
        {
          target: () => platform.target(),
          start: (id, samples, failed) =>
            capture.start(id, preferences.microphone, samples, failed),
          stop: (id, discard) => capture.stop(id, discard),
          transcribe: (samples) => worker.transcribe(samples),
          insert: (text, target) => platform.insert(text, target),
          changed,
        },
        () => preferences.replacements,
      );
      const trustedAudio = (contents: WebContents | null) =>
        contents === audio.webContents;
      session.defaultSession.setPermissionRequestHandler(
        (contents, permission, callback, details) => {
          callback(
            permission === "media" &&
              trustedAudio(contents) &&
              details.isMainFrame &&
              "mediaTypes" in details &&
              details.mediaTypes?.length === 1 &&
              details.mediaTypes?.every((type: string) => type === "audio") ===
                true,
          );
        },
      );
      session.defaultSession.setPermissionCheckHandler(
        (contents, permission, _origin, details) =>
          permission === "media" &&
          trustedAudio(contents) &&
          details.isMainFrame &&
          details.mediaType === "audio",
      );
      session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
        callback({
          cancel:
            !details.url.startsWith(
              pathToFileURL(join(__dirname, "renderer")).href + "/",
            ) && !details.url.startsWith("devtools:"),
        });
      });
      ipcMain.handle("snapshot", (event) => {
        if (!allowed(event, [main, overlay])) throw new Error("unauthorized");
        return snapshot();
      });
      ipcMain.handle("devices", (event) => {
        if (!allowed(event, [main])) throw new Error("unauthorized");
        return capture.devices;
      });
      ipcMain.handle("action", async (event, value: Action) => {
        if (
          !allowed(event, [main, overlay]) ||
          typeof value !== "string" ||
          (event.sender === overlay.webContents &&
            !["copy", "dismiss", "cancel"].includes(value))
        )
          throw new Error("unauthorized");
        try {
          await action(value);
        } catch {
          notice =
            "That action could not finish. Check permissions and try again.";
          changed();
        }
      });
      ipcMain.handle("preferences", async (event, value: unknown) => {
        if (!allowed(event, [main]) || dictation.busy || savingPreferences)
          throw new Error("preferences_busy");
        const next = validatePreferences(value),
          triggerChanged = next.trigger !== preferences.trigger;
        savingPreferences = true;
        try {
          await writeFile(
            join(app.getPath("userData"), "settings.tmp"),
            JSON.stringify(next),
            { mode: 0o600 },
          );
          await rename(
            join(app.getPath("userData"), "settings.tmp"),
            join(app.getPath("userData"), "settings.json"),
          );
          preferences = next;
          if (triggerChanged && stopTrigger) await enableTrigger();
          changed();
        } finally {
          savingPreferences = false;
        }
      });
      ipcMain.on("audio-reply", (event, reply) => {
        if (
          event.sender === audio.webContents &&
          event.senderFrame === audio.webContents.mainFrame
        )
          capture.receive(reply);
      });
      audio.webContents.on("render-process-gone", () => {
        void dictation.cancel("The microphone stopped. Reopen Textify.");
      });
      main.on("close", (event) => {
        if (!quitting) {
          event.preventDefault();
          main.hide();
        }
      });
      main.on("blur", () => {
        if (["armed", "recording"].includes(dictation.phase) && !stopTrigger)
          void dictation.cancel();
      });
      Menu.setApplicationMenu(
        Menu.buildFromTemplate([
          ...(process.platform === "darwin"
            ? [
                {
                  label: "Textify",
                  submenu: [
                    { label: "Open Textify", click: showMain },
                    { role: "quit" as const },
                  ],
                },
              ]
            : []),
          { role: "editMenu" },
          { role: "windowMenu" },
        ]),
      );
      tray = new Tray(
        nativeImage
          .createFromPath(join(resources, "icon.png"))
          .resize({ width: 20, height: 20 }),
      );
      tray.setToolTip("Textify");
      tray.setContextMenu(
        Menu.buildFromTemplate([
          { label: "Open Textify", click: showMain },
          { type: "separator" },
          { label: "Quit Textify", click: () => app.quit() },
        ]),
      );
      tray.on("click", showMain);
      await Promise.all([
        main.loadFile(page),
        audio.loadFile(page, { query: { mode: "audio" } }),
        overlay.loadFile(page, { query: { mode: "overlay" } }),
      ]);
      main.show();
      try {
        await models.init();
        initialized = true;
        if (models.installed) await loadModel();
      } catch {
        notice =
          "The bundled model catalog could not be verified. Reinstall this preview.";
      }
      if (!smoke && !wayland) await enableTrigger();
      changed();
    })
    .catch(() => {
      dialog.showErrorBox(
        "Textify could not start",
        "Reopen Textify or reinstall this preview.",
      );
      app.quit();
    });
  app.on("window-all-closed", () => {});
  app.on("before-quit", (event) => {
    if (cleaned) return;
    event.preventDefault();
    if (quitting) return;
    quitting = true;
    clearTimeout(broadcastTimer);
    stopTrigger?.();
    models?.cancel();
    worker?.stop();
    capture?.shutdown();
    audio?.destroy();
    void (async () => {
      await dictation?.cancel();
      overlay?.destroy();
      tray?.destroy();
      cleaned = true;
      app.quit();
    })();
  });
}
