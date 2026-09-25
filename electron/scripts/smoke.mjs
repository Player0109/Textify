import { _electron as electron } from "playwright";
import {
  mkdtemp,
  mkdir,
  rm,
  copyFile,
  readFile,
  writeFile,
  cp,
  stat,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
const data = await mkdtemp(join(tmpdir(), "textify-electron-smoke-"));
const today = new Date();
const dayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
await writeFile(join(data, "activity.json"), JSON.stringify({
  version: 1,
  days: [{ date: dayKey, words: 500, dictations: 4, recordingSeconds: 120, estimatedTimeSavedSeconds: 630 }],
}));
const env = { ...process.env, TEXTIFY_ELECTRON_TEST_DATA: data };
const fixtureID = process.env.TEXTIFY_MODEL_ID ?? "ggml-small.en-q5_1";
const noGPU = process.env.TEXTIFY_EXPECT_NO_GPU === "1";
if (noGPU) env.GGML_VK_VISIBLE_DEVICES = "";
delete env.ELECTRON_RUN_AS_NODE;
let app;
try {
  const args = [resolve("."), "--smoke"];
  if (process.env.TEXTIFY_MODEL_FIXTURE) {
    await mkdir(join(data, "models"));
    if ((await stat(process.env.TEXTIFY_MODEL_FIXTURE)).isDirectory()) {
      await cp(
        process.env.TEXTIFY_MODEL_FIXTURE,
        join(data, "models", fixtureID),
        { recursive: true },
      );
    } else
      await copyFile(
        process.env.TEXTIFY_MODEL_FIXTURE,
        join(
          data,
          `models/${fixtureID}.${fixtureID.startsWith("confucius") || fixtureID.startsWith("qwen") || fixtureID.startsWith("parakeet") ? "gguf" : "bin"}`,
        ),
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
  if (process.env.TEXTIFY_MODEL_FIXTURE && fixtureID !== "ggml-small.en-q5_1") {
    await waitSnapshot(
      (state) => state.models.length > 4 && !state.modelBusy,
      120000,
    );
    const state = await page.evaluate(() => window.textify.snapshot());
    await page.evaluate(
      (preferences) => window.textify.preferences(preferences),
      { ...state.preferences, activeModelID: fixtureID },
    );
    await waitSnapshot((state) => state.ready, 120000);
  }
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.getByRole("heading", { name: "General", exact: true }).waitFor();
  if (process.platform === "darwin")
    assert.equal(
      await app.evaluate(({ app }) => app.dock.isVisible()),
      true,
      "Creating the recording overlay must not hide Textify from the Dock",
    );
  await waitSnapshot((state) =>
    state.models.some((model) => model.id === "ggml-small.en-q5_1"),
  );
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
  assert.equal(await indicator.evaluate(async () => {
    try { await window.textify.activity(); return false; }
    catch { return true; }
  }), true, "The overlay cannot read activity totals");
  await mkdir("artifacts", { recursive: true });
  await page.getByRole("button", { name: "Activity", exact: true }).click();
  await page.getByRole("heading", { name: "Activity", exact: true }).waitFor();
  await page.locator(".activity-summary-primary strong").getByText("500").waitFor();
  assert.equal(await page.getByRole("button", { name: "Month", exact: true }).getAttribute("aria-pressed"), "true");
  await page.getByRole("button", { name: "Week", exact: true }).click();
  await page.getByRole("heading", { name: "Weekly activity" }).waitFor();
  assert.equal(await page.locator(".activity-period").count(), 8);
  await page.getByRole("button", { name: "Day", exact: true }).click();
  await page.getByRole("heading", { name: "Daily activity" }).waitFor();
  assert.equal(await page.locator(".activity-period").count(), 30);
  await page.locator(".activity-period").first().click();
  await page.locator(".activity-summary-primary strong").getByText("0").waitFor();
  await page.getByRole("button", { name: "View all time" }).click();
  await page.getByRole("heading", { name: "All time" }).waitFor();
  await page.locator(".activity-summary-primary strong").getByText("500").waitFor();
  await page.getByRole("button", { name: "Month", exact: true }).click();
  assert.equal(await page.locator(".activity-bar.has-words").count(), 1);
  assert.equal(await page.getByRole("button", { name: "Reset activity data" }).count(), 0);
  assert.equal(await page.evaluate(() => typeof window.textify.resetActivity), "undefined");
  await page.screenshot({ path: "artifacts/activity.png" });
  assert.equal((await page.evaluate(() => window.textify.activity())).totals.words, 500);
  assert.equal(JSON.parse(await readFile(join(data, "activity.json"), "utf8")).days[0].words, 500);
  await page.getByRole("button", { name: "General", exact: true }).click();
  await page.screenshot({ path: "artifacts/dictation.png" });
  await page
    .getByRole("button", { name: "Transcription models", exact: true })
    .click();
  await page.locator(".checkpoint-detail h2").waitFor();
  assert.equal(
    await page.locator(".checkpoint-row .provider-logo img").count(),
    await page.locator(".checkpoint-row").count(),
  );
  assert.equal(await page.locator(".checkpoint-detail-heading .provider-logo img").count(), 1);
  await page.waitForFunction(() =>
    Array.from(document.querySelectorAll(".provider-logo img")).every((image) =>
      image.complete && image.naturalWidth > 0),
  );
  // Source links resolve a catalog ID in the main process; renderer-provided
  // URLs must never become an unrestricted shell.openExternal capability.
  await app.evaluate(({ shell }) => {
    globalThis.modelSourceURLs = [];
    shell.openExternal = async (url) => { globalThis.modelSourceURLs.push(url); };
  });
  const modelLink = page.getByRole("link", { name: /model page$/ });
  const source = await modelLink.getAttribute("href");
  await modelLink.click();
  assert.deepEqual(await app.evaluate(() => globalThis.modelSourceURLs), [source]);
  await page.screenshot({ path: "artifacts/models.png" });
  if (process.platform === "darwin" && process.arch === "arm64") {
    await page.getByLabel("Search models", { exact: true }).fill("Qwen3");
    assert.equal(await page.locator(".checkpoint-row").count(), 2);
    await page.getByRole("button", { name: /Qwen3-ASR 1.7B/ }).click();
    await page
      .getByRole("heading", { name: "Qwen3-ASR 1.7B", exact: true })
      .waitFor();
    assert.equal(await page.locator(".variant").count(), 3);
    await page.screenshot({ path: "artifacts/qwen-models.png" });
    await page.getByLabel("Search models", { exact: true }).fill("Confucius");
    await page
      .getByRole("heading", { name: "Confucius4-R2T2 1.7B", exact: true })
      .waitFor();
    assert.equal(await page.locator(".variant").count(), 3);
    await page.screenshot({ path: "artifacts/confucius-models.png" });
    await page.getByRole("button", { name: "Options for BF16 · Original" }).click();
    await page.getByRole("button", { name: "Import folder", exact: true }).waitFor();
    await page.getByRole("button", { name: "Options for BF16 · Original" }).click();
    const originalSize = await app.evaluate(({ BrowserWindow }) => {
      const main = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().endsWith("/index.html"));
      const size = main.getSize();
      main.setSize(780, 780);
      return size;
    });
    await page.getByRole("link", { name: /model page$/ }).scrollIntoViewIfNeeded();
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "Model browser fits the minimum window width");
    await page.screenshot({ path: "artifacts/models-compact.png" });
    await app.evaluate(({ BrowserWindow }, size) => {
      BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().endsWith("/index.html")).setSize(...size);
    }, originalSize);
    await page
      .getByLabel("Search models", { exact: true })
      .fill("no-such-model");
    assert.equal(await page.locator(".checkpoint-row").count(), 0);
    await page.getByLabel("Search models", { exact: true }).fill("");
    await page.getByRole("button", { name: /Confucius4-R2T2 1.7B/ }).click();
    await page.screenshot({ path: "artifacts/models-simplified.png" });
  }
  assert.equal(await page.evaluate(async () => {
    try { await window.textify.model({ action: "source", id: "https://example.com" }); return false; }
    catch { return true; }
  }), true);
  const sourceID = (await page.evaluate(() => window.textify.snapshot())).models[0].id;
  assert.equal(await indicator.evaluate(async (id) => {
    try { await window.textify.model({ action: "source", id }); return false; }
    catch { return true; }
  }, sourceID), true, "The overlay cannot open model links");
  assert.deepEqual(await app.evaluate(() => globalThis.modelSourceURLs), [source]);
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
  await page.getByLabel("Custom word").fill("Textify");
  await page.getByRole("button", { name: "Add word", exact: true }).click();
  await waitSnapshot(
    (state) =>
      state.preferences.customWords.includes("Textify") && !state.modelBusy,
  );
  await page
    .getByRole("button", { name: "Remove word", exact: true })
    .waitFor();
  const persisted = JSON.parse(
    await readFile(join(data, "settings.json"), "utf8"),
  );
  assert.deepEqual(persisted.customWords, ["Textify"]);
  await page.screenshot({ path: "artifacts/vocabulary.png" });
  await page.getByRole("button", { name: "General", exact: true }).click();
  assert.equal(await page.getByLabel("Launch at login").isDisabled(), true);
  await page.getByLabel("Launch at login").scrollIntoViewIfNeeded();
  await page.screenshot({ path: "artifacts/general.png" });
  await page.getByRole("button", { name: "General", exact: true }).click();
  const settings = page.locator(".floating-settings");
  await settings.scrollIntoViewIfNeeded();
  const reset = page.getByRole("button", { name: "Reset Position & Scale" });
  assert.equal(await reset.isDisabled(), true);
  await page.getByLabel("Adjust X Offset", { exact: true }).fill("30");
  await page.getByLabel("Adjust X Offset", { exact: true }).press("Tab");
  await waitSnapshot((state) => state.preferences.overlay.x === 30);
  await page.waitForFunction(
    () => !document.querySelector('input[aria-label="X Offset"]').disabled,
  );
  await page
    .getByRole("slider", { name: "X Offset", exact: true })
    .press("ArrowRight");
  await waitSnapshot((state) => state.preferences.overlay.x === 31);
  const slider = page.getByRole("slider", { name: "X Offset", exact: true });
  await page.waitForFunction(() => {
    const input = document.querySelector('input[aria-label="X Offset"]');
    return !input.disabled && input.value === "31";
  });
  const track = await slider.boundingBox();
  await page.mouse.move(track.x + track.width / 2, track.y + track.height / 2);
  await page.mouse.down();
  await page.mouse.move(
    track.x + track.width * 0.7,
    track.y + track.height / 2,
    { steps: 8 },
  );
  const dragged = Number(await slider.inputValue());
  assert.ok(dragged > 31);
  assert.equal(
    (await page.evaluate(() => window.textify.snapshot())).preferences.overlay
      .x,
    31,
    "Dragging previews locally before committing on release",
  );
  await page.mouse.up();
  await waitSnapshot((state) => state.preferences.overlay.x === dragged);
  await page.getByLabel("Adjust X Offset", { exact: true }).fill("0");
  await page.getByLabel("Adjust X Offset", { exact: true }).press("Tab");
  await waitSnapshot((state) => state.preferences.overlay.x === 0);
  const previewY = await page
    .locator(".floating-mini")
    .evaluate((node) => parseFloat(node.style.top));
  await page.getByLabel("Adjust Y Offset", { exact: true }).fill("70");
  await page.getByLabel("Adjust Y Offset", { exact: true }).press("Tab");
  await waitSnapshot((state) => state.preferences.overlay.y === 70);
  assert.ok(
    (await page
      .locator(".floating-mini")
      .evaluate((node) => parseFloat(node.style.top))) < previewY,
  );
  await page.getByLabel("Adjust Scale", { exact: true }).fill("75");
  await page.getByLabel("Adjust Scale", { exact: true }).press("Tab");
  await waitSnapshot((state) => state.preferences.overlay.scale === 0.75);
  await page
    .getByRole("button", { name: "Increase Scale", exact: true })
    .click();
  await waitSnapshot((state) => state.preferences.overlay.scale === 0.8);
  await page
    .getByRole("button", { name: "Decrease Scale", exact: true })
    .click();
  await waitSnapshot((state) => state.preferences.overlay.scale === 0.75);
  assert.deepEqual(
    JSON.parse(await readFile(join(data, "settings.json"), "utf8")).overlay,
    { x: 0, y: 70, scale: 0.75 },
  );
  await page.getByRole("button", { name: "Vocabulary", exact: true }).click();
  await page.getByRole("button", { name: "General", exact: true }).click();
  assert.equal(
    await page.getByLabel("Adjust Scale", { exact: true }).inputValue(),
    "75",
  );
  await settings.screenshot({ path: "artifacts/floating-icon-settings.png" });
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()
      .find((window) => !window.webContents.getURL().includes("mode="))
      .setSize(780, 1000),
  );
  await settings.screenshot({
    path: "artifacts/floating-icon-settings-compact.png",
  });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
    true,
    "Floating controls must fit the minimum window width",
  );
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()
      .find((window) => !window.webContents.getURL().includes("mode="))
      .setSize(1120, 780),
  );
  await page.getByLabel("Adjust X Offset", { exact: true }).fill("2500");
  await page.getByLabel("Adjust X Offset", { exact: true }).press("Tab");
  await waitSnapshot((state) => state.preferences.overlay.x === 2000);
  await reset.click();
  await waitSnapshot(
    (state) =>
      state.preferences.overlay.x === 0 &&
      state.preferences.overlay.y === 0 &&
      state.preferences.overlay.scale === 1,
  );
  assert.equal(await reset.isDisabled(), true);
  await page.getByRole("button", { name: "Privacy", exact: true }).click();
  await page
    .getByRole("heading", { name: "Your speech stays here." })
    .waitFor();
  const accessibilityIcon = page.locator(".privacy .accessibility-heading img");
  if (await accessibilityIcon.count())
    await accessibilityIcon.evaluate((img) => img.decode());
  await page.screenshot({ path: "artifacts/privacy.png" });
  if (process.env.TEXTIFY_MODEL_FIXTURE && noGPU) {
    const state = await waitSnapshot(
      (state) => !state.modelBusy && state.message.includes("No supported GPU"),
    );
    assert.equal(state.ready, false);
    assert.equal(state.gpu, null);
    await page.getByRole("button", { name: "General", exact: true }).click();
    assert.equal(
      await page.getByRole("button", { name: "Hold to dictate" }).isDisabled(),
      true,
    );
    await page.evaluate(() => window.textify.action("press"));
    assert.equal(
      (await page.evaluate(() => window.textify.snapshot())).phase,
      "idle",
    );
    await page.screenshot({ path: "artifacts/gpu-unavailable.png" });
    console.log(
      "No-GPU error is visible and recording is disabled; no CPU inference was attempted.",
    );
  } else if (process.env.TEXTIFY_MODEL_FIXTURE) {
    const state = await waitSnapshot((state) => state.ready);
    assert.ok(state.gpu?.device);
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
    await page.getByRole("button", { name: "General", exact: true }).click();
    await app.evaluate(({ clipboard }) => {
      clipboard.writeText = async (text) => {
        globalThis.__testCopy = text;
      };
    });
    await page.evaluate(() => window.textify.action("press"));
    await waitSnapshot((state) => state.phase === "recording");
    if (fixtureID.startsWith("confucius")) {
      await waitSnapshot(
        (state) => state.phase === "recording" && state.preview.trim(),
        12000,
      );
      await indicator.screenshot({
        path: "artifacts/overlay-live.png",
        omitBackground: true,
      });
      assert.equal(await indicator.locator(".overlay-transcript").count(), 1);
      const waveform = await indicator.evaluate(async () => {
        const wave = document.querySelector(".overlay-waveform");
        const bars = [...wave.children];
        const heights = [];
        for (let frame = 0; frame < 45; frame++) {
          await new Promise(requestAnimationFrame);
          heights.push(bars.map((bar) => bar.getBoundingClientRect().height));
        }
        return {
          count: bars.length,
          color: getComputedStyle(wave).color,
          unusedWidth:
            wave.getBoundingClientRect().right -
            bars.at(-1).getBoundingClientRect().right,
          moving: heights.some((row) =>
            row.some((height, index) => height !== heights[0][index]),
          ),
          maxStep: Math.max(
            ...heights
              .slice(1)
              .flatMap((row, frame) =>
                row.map((height, index) =>
                  Math.abs(height - heights[frame][index]),
                ),
              ),
          ),
          hints: document.querySelectorAll(".overlay-hint").length,
        };
      });
      assert.equal(waveform.count, 34);
      assert.equal(waveform.color, "rgb(183, 190, 201)");
      assert.ok(
        Math.abs(waveform.unusedWidth) < 1,
        "Waveform spans the complete row",
      );
      assert.equal(waveform.hints, 0);
      assert.equal(waveform.moving, true);
      assert.ok(
        waveform.maxStep < 5,
        "Waveform must move continuously rather than jump",
      );
    }
    const recordingDeadline = Date.now() + 12000;
    // Feed the public fixture in real time, through the actual AudioWorklet.
    while (
      (await page.evaluate(() => window.textify.snapshot())).elapsed < 12 &&
      Date.now() < recordingDeadline
    )
      await page.waitForTimeout(100);
    if (fixtureID.startsWith("confucius")) {
      await indicator.screenshot({
        path: "artifacts/overlay-live.png",
        omitBackground: true,
      });
      assert.equal(
        await indicator.evaluate(() => {
          const box = document
            .querySelector(".overlay")
            .getBoundingClientRect();
          return (
            box.x >= 0 &&
            box.y >= 0 &&
            box.right <= innerWidth &&
            box.bottom <= innerHeight
          );
        }),
        true,
        "The expanded preview must fit the floating window",
      );
    }
    await page.evaluate(() => window.textify.action("release"));
    await waitSnapshot((state) => state.phase === "copy", 60000);
    await indicator
      .getByRole("button", { name: "Copy", exact: true })
      .waitFor();
    await indicator.screenshot({
      path: "artifacts/overlay-copy.png",
      omitBackground: true,
    });
    assert.equal(await indicator.locator(".overlay-transcript").count(), 0);
    await indicator.getByRole("button", { name: "Copy", exact: true }).click();
    assert.equal(
      await app.evaluate(() => /fellow Americans/i.test(globalThis.__testCopy)),
      true,
    );
    await waitSnapshot((state) => state.phase === "idle");
    console.log(
      "Fixture MediaStream → AudioWorklet → native recognition → explicit Copy passed without touching the microphone or system clipboard.",
    );
  }
  // Controlled text updates exercise the actual overlay layout/animation without
  // depending on recognition timing, microphone access or another application's UI.
  // Wait for the final capture notification before sending controlled snapshots.
  await indicator.locator(".overlay.idle").waitFor({ state: "attached" });
  const overlayState = await page.evaluate(() => window.textify.snapshot());
  const showPreview = async (preview, identity = {}) => {
    await app.evaluate(
      ({ BrowserWindow }, state) => {
        const overlay = BrowserWindow.getAllWindows().find((window) =>
          window.webContents.getURL().includes("mode=overlay"),
        );
        overlay.setSize(344, 156);
        overlay.showInactive();
        overlay.webContents.send("snapshot", state);
      },
      {
        ...overlayState,
        phase: "recording",
        ...identity,
        preview,
      },
    );
    await indicator.waitForFunction(
      (text) =>
        document.querySelector(".overlay-transcript-content")?.textContent ===
        text,
      preview,
    );
  };
  await showPreview("Words move upward together.");
  const wraps = await indicator.evaluate(() => {
    const content = document.querySelector(".overlay-transcript-content");
    const probe = content.cloneNode(false);
    Object.assign(probe.style, {
      position: "absolute",
      visibility: "hidden",
      width: `${content.offsetWidth}px`,
      transform: "none",
    });
    content.parentElement.append(probe);
    const text = {};
    const phrase =
      "The newest words remain visible as all three lines move upward smoothly together".split(
        " ",
      );
    let words = "";
    for (let index = 0; index < 100; index++) {
      words += `${words ? " " : ""}${phrase[index % phrase.length]}`;
      probe.textContent = words;
      const lines = probe.offsetHeight / 20;
      if (!text[lines]) text[lines] = words;
      if (lines === 5) break;
    }
    probe.remove();
    return text;
  });
  await showPreview(wraps[3]);
  assert.equal(
    await indicator
      .locator(".overlay-transcript-content")
      .evaluate((node) => node.offsetHeight),
    60,
  );
  for (const lines of [4, 5]) {
    // The owner requested always-on animation, including when macOS asks for
    // reduced motion. No overlay preference/control is introduced.
    if (lines === 5) await indicator.emulateMedia({ reducedMotion: "reduce" });
    await indicator.evaluate(() => {
      window.__transcriptMotion = [];
      const sample = () => {
        const node = document.querySelector(".overlay-transcript-content");
        window.__transcriptMotion.push(
          node.getBoundingClientRect().top -
            node.parentElement.getBoundingClientRect().top,
        );
        if (window.__transcriptMotion.length < 25)
          requestAnimationFrame(sample);
      };
      requestAnimationFrame(sample);
    });
    await showPreview(wraps[lines]);
    await indicator.waitForFunction(
      () => window.__transcriptMotion.length === 25,
    );
    const frames = await indicator.evaluate(() => window.__transcriptMotion);
    const end = -(lines - 3) * 20;
    assert.ok(
      frames.some((y) => y < end + 19.9 && y > end + 0.1),
      `Wrapped text must visibly pass through intermediate positions (${lines} lines: ${frames.join(", ")})`,
    );
    assert.ok(
      Math.abs(frames.at(-1) - end) < 0.1,
      "Newest line must settle at the bottom of the three-line viewport",
    );
    assert.ok(
      frames.every((y, index) => index === 0 || y <= frames[index - 1] + 0.1),
      "All lines must move upward together without jumping back",
    );
  }
  await showPreview(`${wraps[5]} a`);
  await indicator.waitForTimeout(180);
  assert.equal(
    await indicator
      .locator(".overlay-transcript-content")
      .evaluate((node) => node.offsetHeight),
    100,
  );
  await indicator.screenshot({
    path: "artifacts/overlay-transcript-scroll.png",
    omitBackground: true,
  });
  await showPreview("A new recording starts at the first line.");
  await indicator.waitForTimeout(180);
  assert.equal(
    await indicator
      .locator(".overlay-transcript-content")
      .evaluate(
        (node) => new DOMMatrixReadOnly(getComputedStyle(node).transform).m42,
      ),
    0,
  );
  await indicator.emulateMedia({ reducedMotion: "no-preference" });
  console.log(
    "Three-to-four-to-five-line transcript movement, intermediate animation frames and always-on motion passed.",
  );

  if (process.platform === "darwin") {
    // Exercise the actual Mac target-icon encoder and the renderer's CSP/image
    // decoding, without recording or sending a paste to another application.
    const target = JSON.parse(
      execFileSync(resolve("resources/textify-platform"), ["target"], {
        encoding: "utf8",
      }),
    );
    assert.match(target.appIcon, /^data:image\/png;base64,/);
    await showPreview(
      "Hello, is it working? If it’s working, how good it is?",
      { application: target.appName, applicationIcon: target.appIcon },
    );
    await indicator
      .locator(".overlay-app-icon img")
      .evaluate((image) => image.decode());
    assert.deepEqual(
      await indicator
        .locator(".overlay-app-icon img")
        .evaluate((image) => [image.naturalWidth, image.naturalHeight]),
      [48, 48],
    );
    await indicator.screenshot({
      path: "artifacts/overlay-app-icon.png",
      omitBackground: true,
    });
    console.log(
      "Native destination icon, in-memory PNG decoding and overlay rendering passed.",
    );
  }
  await page.getByRole("button", { name: "Activity", exact: true }).click();
  const activitySize = await app.evaluate(({ BrowserWindow }) => {
    const window = BrowserWindow.getAllWindows().find((item) => item.webContents.getURL().endsWith("/index.html"));
    const size = window.getSize();
    window.setSize(780, 780);
    return size;
  });
  await page.waitForFunction(() => innerWidth <= 780);
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "Activity fits the minimum window width");
  await page.screenshot({ path: "artifacts/activity-compact.png" });
  await app.evaluate(({ BrowserWindow }, size) => {
    BrowserWindow.getAllWindows().find((item) => item.webContents.getURL().endsWith("/index.html")).setSize(...size);
  }, activitySize);
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
    process.platform === "darwin" ? 4 : 3,
  );
  if (process.platform === "darwin") {
    assert.equal(
      await app.evaluate(({ app, BrowserWindow }) => {
        const overlay = BrowserWindow.getAllWindows().find((window) =>
          window.webContents.getURL().includes("mode=overlay"),
        );
        overlay.showInactive();
        const visible = app.dock.isVisible();
        overlay.hide();
        return visible;
      }),
      true,
      "The Dock must stay visible with the main window closed and overlay shown",
    );
    assert.equal(
      await app.evaluate(({ app, BrowserWindow }) => {
        app.emit("activate");
        return BrowserWindow.getAllWindows()
          .find((window) => !window.webContents.getURL().includes("mode="))
          .isVisible();
      }),
      true,
      "Dock activation must reopen the same main window",
    );
  }
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
