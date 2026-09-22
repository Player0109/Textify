import { _electron as electron } from "playwright";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import assert from "node:assert/strict";

if (!process.argv[2])
  throw new Error("Pass the packaged application executable path.");
const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;
const application = await electron.launch({
  executablePath: resolve(process.argv[2]),
  env,
});
try {
  assert.equal(await application.evaluate(({ app }) => app.isPackaged), true);
  // Audio and overlay windows may finish loading before the settings window.
  await application.firstWindow();
  let page;
  const windowDeadline = Date.now() + 30000;
  while (
    !(page = application
      .windows()
      .find((window) => window.url().endsWith("/index.html")))
  ) {
    if (Date.now() > windowDeadline)
      throw new Error("Settings window did not load");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  await page.getByRole("heading", { name: "Dictation", exact: true }).waitFor();
  const deadline = Date.now() + 30000;
  while (
    (await page.evaluate(() => window.textify.snapshot())).models.length < 4
  ) {
    if (Date.now() > deadline)
      throw new Error("Packaged catalog failed to initialize");
    await page.waitForTimeout(100);
  }
  assert.equal(await page.evaluate(() => typeof window.require), "undefined");
  await mkdir("artifacts", { recursive: true });
  await page.screenshot({ path: "artifacts/packaged-dictation.png" });
  await page.getByRole("button", { name: "Models", exact: true }).click();
  await page.getByRole("heading", { name: "Whisper small.en" }).waitFor();
  console.log(
    "Packaged app launch, verified catalog, isolated renderer, and navigation passed. No recording or paste was requested.",
  );
} finally {
  await application.close();
}
