import { _electron as electron } from "playwright";
import { mkdtemp, mkdir, rm, copyFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";
const data = await mkdtemp(join(tmpdir(), "textify-electron-smoke-"));
const env = { ...process.env, TEXTIFY_ELECTRON_TEST_DATA: data };
delete env.ELECTRON_RUN_AS_NODE;
let app;
try {
  const args = [resolve("."), "--smoke"];
  if (process.env.TEXTIFY_MODEL_FIXTURE) {
    await mkdir(join(data, "models"));
    await copyFile(
      process.env.TEXTIFY_MODEL_FIXTURE,
      join(data, "models/ggml-small.en-q5_1.bin"),
    );
    args.push("--autoplay-policy=no-user-gesture-required");
  }
  app = await electron.launch({ args, env });
  // Audio and overlay windows may finish loading before the settings window.
  await app.firstWindow();
  let page;
  const windowDeadline = Date.now() + 30000;
  while (
    !(page = app
      .windows()
      .find((window) => window.url().endsWith("/index.html")))
  ) {
    if (Date.now() > windowDeadline)
      throw new Error("Settings window did not load");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const waitSnapshot = async (predicate, timeout = 30000) => {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const state = await page.evaluate(() => window.textify.snapshot());
      if (predicate(state)) return state;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error("Timed out waiting for app state");
  };
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.getByRole("heading", { name: "Dictation", exact: true }).waitFor();
  await waitSnapshot((state) => state.models.length === 1);
  assert.equal(await page.evaluate(() => typeof window.require), "undefined");
  assert.equal(await page.evaluate(() => typeof window.process), "undefined");
  const hiddenAudio = app
    .windows()
    .find((window) => window.url().includes("mode=audio"));
  const indicator = app
    .windows()
    .find((window) => window.url().includes("mode=overlay"));
  assert.equal(
    await hiddenAudio.evaluate(
      async () => (await navigator.permissions.query({ name: "camera" })).state,
    ),
    "denied",
  );
  assert.equal(
    await page.evaluate(
      async () =>
        (await navigator.permissions.query({ name: "microphone" })).state,
    ),
    "denied",
  );
  assert.equal(
    await hiddenAudio.evaluate(async () => {
      try {
        await window.textify.snapshot();
        return false;
      } catch {
        return true;
      }
    }),
    true,
  );
  assert.equal(
    await indicator.evaluate(async () => {
      try {
        await window.textify.action("enable-trigger");
        return false;
      } catch {
        return true;
      }
    }),
    true,
  );
  await mkdir("artifacts", { recursive: true });
  await page.screenshot({ path: "artifacts/dictation.png" });
  await page.getByRole("button", { name: "Models", exact: true }).click();
  await page.getByRole("heading", { name: "Whisper small.en" }).waitFor();
  await page.screenshot({ path: "artifacts/models.png" });
  await page.getByRole("button", { name: "Vocabulary", exact: true }).click();
  await page.getByLabel("When I say").fill("text if eye");
  await page.getByLabel("Replace with").fill("Textify");
  await page.getByRole("button", { name: "Add pair" }).click();
  await page.getByRole("button", { name: "Remove", exact: true }).waitFor();
  assert.equal(
    await page.evaluate(
      async () =>
        (await window.textify.snapshot()).preferences.replacements[0]
          .replacement,
    ),
    "Textify",
  );
  await page.getByLabel("When I say").fill("text if eye");
  await page
    .getByLabel("Replace with")
    .fill("Duplicate should stay in the form");
  await page.getByRole("button", { name: "Add pair" }).click();
  await page
    .getByRole("status")
    .filter({ hasText: "Settings could not be saved" })
    .waitFor();
  assert.equal(
    await page.getByLabel("Replace with").inputValue(),
    "Duplicate should stay in the form",
  );
  assert.equal(
    (await page.evaluate(() => window.textify.snapshot())).preferences
      .replacements.length,
    1,
  );
  await page.getByRole("button", { name: "Privacy", exact: true }).click();
  await page
    .getByRole("heading", { name: "Your speech stays here." })
    .waitFor();
  if (process.env.TEXTIFY_MODEL_FIXTURE) {
    await waitSnapshot((state) => state.ready);
    const audioPage = app
      .windows()
      .find((page) => page.url().includes("mode=audio"));
    const sample = (await readFile(".native/whisper/samples/jfk.wav")).toString(
      "base64",
    );
    await audioPage.evaluate((encoded) => {
      navigator.mediaDevices.getUserMedia = async () => {
        const context = new AudioContext({ sampleRate: 48000 });
        const bytes = Uint8Array.from(atob(encoded), (ch) => ch.charCodeAt(0));
        const buffer = await context.decodeAudioData(bytes.buffer);
        const source = context.createBufferSource();
        source.buffer = buffer;
        const destination = context.createMediaStreamDestination();
        source.connect(destination);
        const track = destination.stream.getAudioTracks()[0],
          original = track.stop.bind(track);
        track.stop = () => {
          original();
          source.stop();
          void context.close();
        };
        await context.resume();
        source.start();
        return destination.stream;
      };
    }, sample);
    await page.getByRole("button", { name: "Dictation", exact: true }).click();
    await app.evaluate(({ clipboard }) => {
      clipboard.writeText = (text) => {
        globalThis.__testCopy = text;
      };
    });
    await page.evaluate(() => window.textify.action("press"));
    await waitSnapshot((state) => state.phase === "recording");
    await page.waitForTimeout(12000);
    await page.evaluate(() => window.textify.action("release"));
    await waitSnapshot((state) => state.phase === "copy", 60000);
    await page.getByRole("button", { name: "Copy dictation" }).click();
    assert.equal(
      await app.evaluate(() => /fellow Americans/i.test(globalThis.__testCopy)),
      true,
    );
    assert.equal(
      await page.evaluate(async () => (await window.textify.snapshot()).phase),
      "idle",
    );
    console.log(
      "Fixture MediaStream → AudioWorklet → native recognition → explicit Copy passed without touching the microphone or system clipboard.",
    );
  }
  assert.deepEqual(errors, []);
  // Closing the settings window leaves the utility alive and reopening reuses it.
  await app.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows().find(
      (w) => !w.webContents.getURL().includes("mode="),
    );
    win.close();
  });
  assert.equal(
    await app.evaluate(
      ({ BrowserWindow }) => BrowserWindow.getAllWindows().length,
    ),
    3,
  );
  console.log(
    "Electron launch, isolated renderer, navigation, settings persistence, and close-to-tray checks passed.",
  );
} catch (error) {
  if (app) {
    const page = app.windows().find((page) => !page.url().includes("mode="));
    await page
      ?.screenshot({ path: "artifacts/smoke-failure.png" })
      .catch(() => {});
    if (page)
      console.log(
        await page.evaluate(async () => ({
          phase: (await window.textify.snapshot()).phase,
          buttons: [...document.querySelectorAll("button")].map(
            (button) => button.textContent,
          ),
        })),
      );
  }
  throw error;
} finally {
  await app?.close();
  await rm(data, { recursive: true, force: true });
}
