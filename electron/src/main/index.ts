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
import { basename, dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { Dictation } from "../core/dictation";
import { engineError } from "../core/engine-error";
import { overlayBounds } from "../core/overlay-geometry";
import { Models } from "./models";
import { WhisperWorker } from "./worker";
import { Platform, nativeTrigger } from "./platform";
import { waylandTrigger } from "./wayland";
import { Capture } from "./capture";
import { AccessibilitySetup } from "./accessibility";
import { ActivityStore } from "./activity";
import { defaults, validatePreferences } from "./preferences";
import { linuxStartup, linuxStartupEnabled } from "./startup";
import type { Action, Preferences, Snapshot, ModelCommand } from "../shared";

app.setName("Textify");
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
let accessibilityHelp: BrowserWindow | undefined;
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
let preferences: Preferences = defaults(process.platform, wayland);
const platform = new Platform(resources);
let models: Models,
  worker: WhisperWorker,
  capture: Capture,
  dictation: Dictation;
const activity = new ActivityStore(join(app.getPath("userData"), "activity.json"));
let activityError = false;
let broadcastTimer: ReturnType<typeof setTimeout> | undefined;
const appBundle = dirname(dirname(dirname(process.execPath)));
const accessibility = process.platform === "darwin"
  ? new AccessibilitySetup(
      (prompt) => systemPreferences.isTrustedAccessibilityClient(prompt),
      (granted) => {
        if (granted) {
          accessibilityHelp?.hide();
          if (initialized && !quitting && !smoke && !stopTrigger && !enabling)
            void enableTrigger();
        } else {
          stopTrigger?.();
          stopTrigger = undefined;
          triggerStatus = "Enable Accessibility to use the global shortcut.";
          if (["armed", "recording"].includes(dictation?.phase))
            void dictation.cancel();
        }
        changed();
      },
    )
  : null;
function snapshot(): Snapshot {
  return {
    phase: dictation?.phase ?? "idle",
    message: engineError(worker?.failure) || notice || dictation?.message || "",
    level: dictation?.level ?? 0,
    elapsed: dictation?.elapsed ?? 0,
    preview: dictation?.preview ?? "",
    application: dictation?.application ?? "Textify",
    applicationIcon: dictation?.applicationIcon ?? "",
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
    triggerEnabled: Boolean(stopTrigger),
    accessibility: accessibility ? {
      status: accessibility.status,
      appName: basename(appBundle, ".app"),
      appPath: appBundle,
    } : null,
    ready: Boolean(
      initialized &&
        worker?.ready &&
        models?.installed &&
        models.selected?.languages.includes(preferences.language),
    ),
    gpu: worker?.gpu ?? null,
    modelBusy: modelBusy || Boolean(models?.busy),
    download: models?.progress ?? null,
    preferences,
    models: models?.views() ?? [],
    downloadModelID: models?.progressID ?? null,
    exclusionsAvailable: platform.exclusionsAvailable,
    startupAvailable: app.isPackaged,
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
      const { scale, ...bounds } = overlayBounds(
        area,
        preferences.overlay,
        state.phase === "error" || Boolean(state.preview),
      );
      overlay.setBounds(bounds);
      overlay.webContents.setZoomFactor(scale);
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
function showAccessibilityHelp() {
  if (!accessibilityHelp || accessibilityHelp.isDestroyed()) return;
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  accessibilityHelp.setBounds({
    x: area.x + area.width - 376,
    y: area.y + 56,
    width: 352,
    height: 184,
  });
  accessibilityHelp.showInactive();
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
      if (
        snapshot().ready &&
        !modelBusy &&
        !models.busy &&
        !savingPreferences
      ) {
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
      accessibility && !accessibility.refresh()
    ) {
      triggerStatus =
        "Enable Accessibility to use the global shortcut.";
      return;
    }
    if (wayland) {
      const trigger = await waylandTrigger(events);
      stopTrigger = trigger.stop;
      triggerStatus = `Hold ${trigger.description}`;
    } else {
      stopTrigger = await nativeTrigger(preferences.trigger, events);
      if (quitting || (accessibility && !accessibility.refresh())) {
        stopTrigger?.();
        stopTrigger = undefined;
        return;
      }
      triggerStatus = `Hold ${preferences.trigger === "right-command" ? "Right Command" : preferences.trigger === "right-option" ? "Right Option" : preferences.trigger === "right-control" ? "Right Control" : "Control + Space"}`;
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
    worker.stop();
    if (
      !models.installed ||
      !models.selected?.languages.includes(preferences.language)
    ) {
      notice =
        "Choose an installed model that supports the selected dictation language.";
      return;
    }
    await worker.load(
      models.path,
      preferences.language,
      preferences.customWords,
      models.selected.engine,
    );
    notice = "";
  } catch (error) {
    notice =
      engineError(error) ??
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
      if (
        snapshot().ready &&
        !modelBusy &&
        !models.busy &&
        !savingPreferences
      ) {
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
      await dictation.copy((text) => clipboard.writeText(text));
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
    case "permission-settings":
      if (active) break;
      if (accessibility) {
        if (accessibility.refresh()) break;
        accessibility.request(action === "permissions");
        await shell.openExternal(
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        );
        if (!accessibility.refresh()) showAccessibilityHelp();
      } else
        notice = "Use your system privacy settings to allow microphone access.";
      break;
    case "reveal-app":
      if (accessibility) shell.showItemInFolder(appBundle);
      break;
    case "enable-trigger":
      if (!active) await enableTrigger();
      break;
    case "cancel-download":
      models.cancel();
      break;
    case "download":
    case "import":
      await modelAction({ action, id: preferences.activeModelID });
      break;
    default:
      throw new Error("unsupported_action");
  }
  changed();
}

async function setStartup(enabled: boolean) {
  if (!app.isPackaged) throw new Error("startup_requires_installation");
  if (process.platform === "linux")
    await linuxStartup(
      app.getPath("appData"),
      process.env.APPIMAGE || process.execPath,
      enabled,
    );
  else
    app.setLoginItemSettings({
      openAtLogin: enabled,
      path: process.execPath,
      args: ["--background"],
    });
}
async function savePreferences(value: unknown) {
  if (dictation.busy || modelBusy || models.busy || savingPreferences)
    throw new Error("preferences_busy");
  const next = validatePreferences(value),
    previous = preferences;
  const changedModel =
    next.activeModelID !== previous.activeModelID ||
    next.language !== previous.language ||
    JSON.stringify(next.customWords) !== JSON.stringify(previous.customWords);
  if (
    next.language !== previous.language &&
    !models.get(next.activeModelID).languages.includes(next.language)
  )
    throw new Error("language_incompatible");
  savingPreferences = true;
  try {
    await writeFile(
      join(app.getPath("userData"), "settings.tmp"),
      JSON.stringify(next),
      { mode: 0o600 },
    );
    const startupChanged = next.launchAtLogin !== previous.launchAtLogin;
    if (startupChanged) await setStartup(next.launchAtLogin);
    try {
      await rename(
        join(app.getPath("userData"), "settings.tmp"),
        join(app.getPath("userData"), "settings.json"),
      );
    } catch (error) {
      if (startupChanged) await setStartup(previous.launchAtLogin);
      throw error;
    }
    preferences = next;
    notice = "";
    models.id = next.activeModelID;
    if (changedModel) {
      worker.stop();
      if (models.installed) await loadModel();
    }
    if (next.trigger !== previous.trigger && stopTrigger) await enableTrigger();
    changed();
  } finally {
    savingPreferences = false;
  }
}
async function modelAction(command: ModelCommand) {
  if (command?.action === "source" && typeof command.id === "string") {
    const source = new URL(models.get(command.id).source);
    if (source.protocol !== "https:" || source.username || source.password)
      throw new Error("model_source");
    await shell.openExternal(source.href);
    return;
  }
  if (
    dictation.busy ||
    modelBusy ||
    models.busy ||
    savingPreferences ||
    !initialized
  )
    throw new Error("model_busy");
  if (
    !command ||
    !["download", "import", "use", "verify", "remove"].includes(
      command.action,
    ) ||
    typeof command.id !== "string"
  )
    throw new Error("model_command");
  const model = models.get(command.id);
  if (command.action === "remove") {
    const answer = await dialog.showMessageBox(main, {
      type: "question",
      message: `Remove ${model.name} from this device?`,
      detail:
        "The downloaded model and its partial download will be removed. Your settings and vocabulary are kept.",
      buttons: ["Cancel", "Remove model"],
      cancelId: 0,
      defaultId: 0,
    });
    if (answer.response !== 1 || dictation.busy || modelBusy || models.busy)
      return;
    if (models.id === command.id) worker.stop();
    await models.remove(command.id);
  } else if (command.action === "use") {
    if (model.status !== "installed") throw new Error("model_not_ready");
    let language = preferences.language;
    if (!model.languages.includes(language)) {
      const answer = await dialog.showMessageBox(main, {
        type: "question",
        message: `Use ${model.name} in ${model.languages[0] === "en" ? "English" : model.languages[0]}?`,
        detail:
          "This model does not support the currently selected language in this preview.",
        buttons: ["Cancel", "Change language and use"],
        cancelId: 0,
        defaultId: 0,
      });
      if (answer.response !== 1) return;
      language = model.languages[0];
    }
    await models.verify(command.id);
    await savePreferences({
      ...preferences,
      activeModelID: command.id,
      language,
    });
    if (!worker.ready) await loadModel();
  } else if (command.action === "verify") {
    await models.verify(command.id);
    if (models.id === command.id) await loadModel();
  } else {
    let source: string | undefined;
    if (command.action === "import") {
      const choice = await dialog.showOpenDialog(main, {
        title: `Choose the exact ${model.name} model`,
        properties: [model.directory ? "openDirectory" : "openFile"],
        filters: model.directory
          ? []
          : [
              {
                name: model.variant,
                extensions: [model.engine === "whisper_cpp" ? "bin" : "gguf"],
              },
            ],
      });
      if (choice.canceled || dictation.busy || modelBusy || models.busy) return;
      source = choice.filePaths[0];
    }
    if (models.id === command.id) worker.stop();
    await models.install(source, command.id);
    if (models.id === command.id) await loadModel();
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
      await activity.load().catch(() => { activityError = true; });
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
      if (app.isPackaged)
        preferences.launchAtLogin =
          process.platform === "linux"
            ? await linuxStartupEnabled(app.getPath("appData"))
            : app.getLoginItemSettings({
                path: process.execPath,
                args: ["--background"],
              }).openAtLogin;
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
        width: 1120,
        height: 780,
        minWidth: 780,
        minHeight: 600,
        title: "Textify",
        backgroundColor: "#11151c",
        show: false,
      });
      main.on("focus", () => accessibility?.refresh());
      accessibility?.refresh();
      audio = createWindow({ show: false, width: 1, height: 1 });
      overlay = createWindow({
        type: process.platform === "darwin" ? "panel" : undefined,
        width: 344,
        height: 88,
        frame: false,
        transparent: true,
        alwaysOnTop: true,
        skipTaskbar: true,
        focusable: false,
        resizable: false,
        show: false,
      });
      // A nonactivating Mac panel can join fullscreen Spaces without turning
      // the whole application into a menu-bar-only process and hiding its Dock icon.
      overlay.setVisibleOnAllWorkspaces(true, {
        visibleOnFullScreen: true,
        skipTransformProcessType: true,
      });
      if (accessibility) {
        accessibilityHelp = createWindow({
          width: 352,
          height: 184,
          frame: false,
          transparent: true,
          alwaysOnTop: true,
          skipTaskbar: true,
          resizable: false,
          show: false,
        });
      }
      capture = new Capture(audio);
      dictation = new Dictation(
        {
          target: async () => {
            const target = await platform.target();
            if (
              preferences.exclusions.length &&
              platform.exclusionsAvailable &&
              !target?.appID
            )
              throw new Error("target_unavailable");
            return target
              ? {
                  ...target,
                  excluded: preferences.exclusions.some(
                    (entry) => entry.id === target.appID,
                  ),
                }
              : null;
          },
          start: (id, samples, failed) =>
            capture.start(id, preferences.microphone, samples, failed),
          stop: (id, discard) => capture.stop(id, discard),
          transcribe: (samples) => worker.transcribe(samples),
          streaming: () => (worker.streaming ? worker : undefined),
          insert: (text, target) => platform.insert(text, target),
          completed: (result) => {
            if (!activityError)
              void activity.record(result).catch(() => {
                activityError = true;
              });
          },
          changed,
        },
        () => preferences.replacements,
        () => Date.now(),
        () => preferences.language,
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
      ipcMain.handle("activity", async (event) => {
        if (!allowed(event, [main])) throw new Error("unauthorized");
        if (activityError) throw new Error("activity_unavailable");
        await activity.flush();
        return activity.snapshot();
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
      ipcMain.handle("preferences", async (event, value) => {
        if (!allowed(event, [main])) throw new Error("unauthorized");
        await savePreferences(value);
        event.sender.send("snapshot", snapshot());
      });
      ipcMain.handle("model", async (event, command) => {
        if (!allowed(event, [main])) throw new Error("unauthorized");
        try {
          await modelAction(command);
        } catch {
          notice =
            command?.action === "source"
              ? "The model page could not open. Try the link again."
              : "The model action could not finish. Check the model, language, and available storage. Interrupted downloads can be resumed.";
          changed();
          throw new Error("model_action_failed");
        }
      });
      ipcMain.handle("apps", async (event) => {
        if (!allowed(event, [main])) throw new Error("unauthorized");
        return platform.apps();
      });
      ipcMain.on("accessibility-help", (event, command) => {
        if (
          !accessibilityHelp ||
          !allowed(event, [accessibilityHelp]) ||
          !accessibility ||
          accessibility.refresh()
        ) return;
        if (command === "drag" && appBundle.endsWith(".app")) {
          event.sender.startDrag({
            file: appBundle,
            icon: nativeImage.createFromPath(join(resources, "icon.png")).resize({ width: 64, height: 64 }),
          });
        } else if (command === "dismiss") accessibilityHelp.hide();
        else if (command === "reveal") shell.showItemInFolder(appBundle);
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
        ...(accessibilityHelp
          ? [accessibilityHelp.loadFile(page, { query: { mode: "accessibility-help" } })]
          : []),
      ]);
      const openedAtLogin =
        process.platform === "darwin" &&
        app.getLoginItemSettings().wasOpenedAtLogin;
      if (!process.argv.includes("--background") && !openedAtLogin) main.show();
      try {
        await models.init(preferences.activeModelID);
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
    accessibility?.stop();
    stopTrigger?.();
    models?.cancel();
    worker?.stop();
    capture?.shutdown();
    audio?.destroy();
    void (async () => {
      await dictation?.cancel();
      await activity.flush().catch(() => {});
      overlay?.destroy();
      accessibilityHelp?.destroy();
      tray?.destroy();
      cleaned = true;
      // A native Cmd+Q can drain this promise before before-quit returns.
      // Let Electron finish cancelling that request before starting another.
      setImmediate(() => app.quit());
    })();
  });
}
