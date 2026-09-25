import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readdir, readFile, writeFile, copyFile, rm } from "node:fs/promises";
import { verifyProductionInstallers } from "./mac-release.mjs";
const production = process.argv.slice(2).includes("--production");
if (process.argv.slice(2).some((arg) => arg !== "--production"))
  throw new Error("Only --production is supported");
if (production) {
  await rm("release/SHA256SUMS.txt", { force: true });
  await rm("release/RELEASE_INSTALL.md", { force: true });
}
const { version } = JSON.parse(await readFile("package.json", "utf8"));
const files = (await readdir("release"))
  .filter(
    (name) =>
      name.startsWith(`Textify-${version}-`) &&
      /\.(dmg|exe|AppImage|deb)$/.test(name),
  )
  .sort();
if (!files.length) throw new Error("No preview installers found");
if (production) verifyProductionInstallers(files, version);
const lines = [];
for (const file of files) {
  const hash = createHash("sha256");
  for await (const bytes of createReadStream(`release/${file}`))
    hash.update(bytes);
  lines.push(`${hash.digest("hex")}  ${file}`);
}
await writeFile("release/SHA256SUMS.txt", `${lines.join("\n")}\n`);
const installNotes = production ? "RELEASE_INSTALL.md" : "PREVIEW_INSTALL.md";
await copyFile(installNotes, `release/${installNotes}`);
console.log(`Checksums prepared for ${files.length} installer(s).`);
