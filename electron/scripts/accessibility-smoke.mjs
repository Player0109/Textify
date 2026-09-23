import { _electron as electron } from "playwright";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";

if (process.platform !== "darwin") throw new Error("This check covers macOS Accessibility setup.");
const data = await mkdtemp(join(tmpdir(), "textify-accessibility-smoke-"));
const env = { ...process.env, TEXTIFY_ELECTRON_TEST_DATA: data };
delete env.ELECTRON_RUN_AS_NODE;
let app;
try {
  app = await electron.launch({ args: [resolve("."), "--smoke"], env });
  await app.firstWindow();
  const page = await app.waitForEvent("window", {
    predicate: (window) => window.url().endsWith("/index.html"),
    timeout: 1000,
  }).catch(() => app.windows().find((window) => window.url().endsWith("/index.html")));
  assert.ok(page, "Main window loads");
  await page.getByRole("heading", { name: "General", exact: true }).waitFor();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  // Substitute only OS boundaries in this isolated test process. Never alter
  // real TCC grants or open Settings/Finder while exercising the renderer.
  await app.evaluate(({ BrowserWindow, systemPreferences, shell }) => {
    globalThis.permissionTest = { granted: false, prompts: 0, urls: [], paths: [] };
    systemPreferences.isTrustedAccessibilityClient = (prompt) => {
      if (prompt) globalThis.permissionTest.prompts++;
      return globalThis.permissionTest.granted;
    };
    shell.openExternal = async (url) => { globalThis.permissionTest.urls.push(url); };
    shell.showItemInFolder = (path) => { globalThis.permissionTest.paths.push(path); };
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().endsWith("/index.html")).emit("focus");
  });
  const card = page.getByRole("region", { name: "Accessibility setup" });
  await card.getByRole("status").filter({ hasText: "Setup needed" }).waitFor();
  const before = await page.evaluate(() => window.textify.snapshot());
  assert.equal(before.accessibility.appPath.endsWith("Electron.app"), true);
  assert.equal(before.accessibility.appName, "Electron");
  await card.getByRole("button", { name: "Enable Accessibility", exact: true }).click();
  await card.getByRole("status").filter({ hasText: "Waiting for permission" }).waitFor();
  await card.getByRole("button", { name: "Open Settings", exact: true }).click();
  let calls = await app.evaluate(() => globalThis.permissionTest);
  assert.equal(calls.prompts, 1, "Reopening settings does not repeat the native prompt");
  assert.deepEqual(calls.urls, Array(2).fill("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"));
  const helper = app.windows().find((window) => window.url().includes("mode=accessibility-help"));
  assert.ok(helper, "The draggable app helper loads");
  await helper.getByRole("dialog", { name: "Add Textify to Accessibility" }).waitFor();
  await mkdir("artifacts", { recursive: true });
  await helper.screenshot({ path: "artifacts/accessibility-drag-helper.png" });
  assert.equal(await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().includes("mode=accessibility-help")).isVisible()
  ), true, "The helper floats above Settings");
  await app.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().includes("mode=accessibility-help"));
    globalThis.permissionTest.drags = [];
    win.webContents.startDrag = ({ file, icon }) => {
      globalThis.permissionTest.drags.push({ file, iconReady: !icon.isEmpty() });
    };
  });
  await helper.getByRole("button", { name: "Drag Textify into the Accessibility list" }).dispatchEvent("dragstart");
  calls = await app.evaluate(() => globalThis.permissionTest);
  assert.deepEqual(calls.drags, [{ file: before.accessibility.appPath, iconReady: true }]);
  await page.evaluate(() => window.textify.accessibilityHelp("dismiss"));
  assert.equal(await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().includes("mode=accessibility-help")).isVisible()
  ), true, "The main renderer cannot control the helper");
  await helper.getByRole("button", { name: "Close helper" }).click();
  assert.equal(await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().includes("mode=accessibility-help")).isVisible()
  ), false, "The helper can be dismissed");
  await card.getByRole("button", { name: "Open Settings", exact: true }).click();
  await card.locator("summary").click();
  await card.getByRole("button", { name: "Show Electron in Finder", exact: true }).click();
  calls = await app.evaluate(() => globalThis.permissionTest);
  assert.deepEqual(calls.paths, [before.accessibility.appPath]);
  const overlay = app.windows().find((window) => window.url().includes("mode=overlay"));
  for (const action of ["permissions", "permission-settings", "reveal-app"]) {
    assert.equal(await overlay.evaluate(async (value) => {
      try { await window.textify.action(value); return false; }
      catch { return true; }
    }, action), true, "Only the main window can perform permission actions");
  }
  await page.getByRole("button", { name: "Privacy", exact: true }).click();
  await card.getByRole("status").filter({ hasText: "Waiting for permission" }).waitFor();
  await card.scrollIntoViewIfNeeded();
  await mkdir("artifacts", { recursive: true });
  await page.screenshot({ path: "artifacts/accessibility-waiting.png" });
  await app.evaluate(({ BrowserWindow }) => {
    const main = BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().endsWith("/index.html"));
    main.setSize(780, 780);
  });
  await card.scrollIntoViewIfNeeded();
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "No horizontal overflow at minimum width");
  await page.screenshot({ path: "artifacts/accessibility-compact.png" });
  // Approval arrives while Settings is frontmost: the timer must detect it
  // without a manual Refresh or Enable global trigger click.
  await app.evaluate(() => { globalThis.permissionTest.granted = true; });
  await card.getByRole("status").filter({ hasText: "Enabled" }).waitFor();
  assert.equal(await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().includes("mode=accessibility-help")).isVisible()
  ), false, "Approval hides the helper");
  assert.equal((await page.evaluate(() => window.textify.snapshot())).accessibility.status, "granted");
  await page.getByRole("button", { name: "General", exact: true }).click();
  assert.equal(await card.count(), 0, "Completed setup no longer obstructs Dictation");
  await app.evaluate(({ BrowserWindow }) => {
    globalThis.permissionTest.granted = false;
    BrowserWindow.getAllWindows().find((window) => window.webContents.getURL().endsWith("/index.html")).emit("focus");
  });
  await card.getByRole("status").filter({ hasText: "Setup needed" }).waitFor();
  assert.equal((await app.evaluate(() => globalThis.permissionTest)).prompts, 1, "Revocation does not display a proactive prompt");
  assert.deepEqual(errors, []);
  console.log("Accessibility setup passed: prompt, Settings link, draggable exact app bundle, helper dismissal, waiting/granted/revoked UI, Finder fallback, narrow layout and IPC isolation. OS boundaries were mocked; no permissions changed.");
} finally {
  await app?.close();
  await rm(data, { recursive: true, force: true });
}
