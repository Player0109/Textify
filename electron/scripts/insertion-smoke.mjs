import { _electron as electron } from "playwright";
import { spawn } from "node:child_process";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import assert from "node:assert/strict";
if (process.platform === "linux")
  throw new Error(
    "Linux uses explicit Copy; no automatic-insertion helper is exposed.",
  );
const directory = await mkdtemp(join(tmpdir(), "textify-insertion-"));
const fixture = join(directory, "fixture.cjs");
await writeFile(
  fixture,
  `const {app,BrowserWindow}=require('electron'); app.setPath('userData', ${JSON.stringify(directory)}); app.commandLine.appendSwitch('force-renderer-accessibility'); app.whenReady().then(async()=>{app.setAccessibilitySupportEnabled(true); const window=new BrowserWindow({width:600,height:350,webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false}}); await window.loadURL('data:text/html,<title>Textify insertion test</title><label>Public test text<textarea id="text"></textarea></label><label>Password test<input id="password" type="password"></label>'); window.show();window.focus();}); app.on('window-all-closed',()=>app.quit());`,
);
function native(args, input = "") {
  return new Promise((resolveResult, reject) => {
    const child = spawn(
      resolve(
        `resources/textify-platform${process.platform === "win32" ? ".exe" : ""}`,
      ),
      args,
      { stdio: "pipe", windowsHide: true },
    );
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("Insertion helper timed out"));
    }, 10000);
    let output = "";
    child.stdout.on("data", (bytes) => (output += bytes));
    child.stderr.resume();
    child.on("error", reject);
    child.on("close", (code) => {
      clearTimeout(timer);
      try {
        if (code) throw new Error("Insertion helper failed");
        resolveResult(JSON.parse(output));
      } catch (error) {
        reject(error);
      }
    });
    child.stdin.on("error", () => {});
    child.stdin.end(input);
  });
}
let application;
try {
  const env = { ...process.env };
  delete env.ELECTRON_RUN_AS_NODE;
  application = await electron.launch({ args: [fixture], env });
  const page = await application.firstWindow();
  await page.locator("#text").focus();
  await application.evaluate(({ BrowserWindow, app }) => {
    BrowserWindow.getAllWindows()[0].focus();
    app.focus({ steal: true });
  });
  await page.waitForTimeout(400);
  await application.evaluate(async ({ clipboard }) => {
    globalThis.__snapshotClipboard = async () =>
      Promise.all(
        (await clipboard.read()).map(async (item) =>
          Promise.all(
            [...item.types].sort().map(async (type) => {
              const value = await item.getType(type);
              return [
                type,
                value instanceof Blob
                  ? Buffer.from(await value.arrayBuffer()).toString("base64")
                  : JSON.stringify(value),
              ];
            }),
          ),
        ),
      );
    globalThis.__clipboardBaseline = JSON.stringify(
      await globalThis.__snapshotClipboard(),
    );
  });
  const target = await native(["target"]);
  const pid = target.target.split(":")[process.platform === "win32" ? 1 : 0];
  assert.equal(
    Number(pid),
    application.process().pid,
    "Only the owned test app may receive paste",
  );
  assert.equal(target.secure, false);
  const result = await native(
    ["paste", target.target],
    "Textify public insertion fixture.",
  );
  assert.equal(
    result.status,
    "sent",
    "Automatic paste requires Accessibility and a restorable clipboard",
  );
  await page.waitForFunction(
    () =>
      document.querySelector("#text").value ===
      "Textify public insertion fixture.",
  );
  assert.equal(
    await application.evaluate(
      async () =>
        globalThis.__clipboardBaseline ===
        JSON.stringify(await globalThis.__snapshotClipboard()),
    ),
    true,
    "All original clipboard formats must be restored",
  );
  assert.equal(
    (await native(["paste", "999999999:999999999"], "must not paste")).status,
    "skipped",
  );
  await page.locator("#password").focus();
  await page.waitForTimeout(300);
  assert.equal(
    (await native(["target"])).secure,
    true,
    "A password field must be positively detected",
  );
  assert.equal(
    (await native(["paste", target.target], "must not paste")).status,
    "skipped",
  );
  assert.equal(await page.locator("#password").inputValue(), "");
  console.log(
    "Native insertion into the owned test app, clipboard restoration, target mismatch, and password-field rejection passed. No microphone or personal text was used.",
  );
} finally {
  await application?.close();
  await rm(directory, { recursive: true, force: true });
}
