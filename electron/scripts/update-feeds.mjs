import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { access, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
// electron-builder's own blockmap writer, so the result matches its format.
import { buildBlockMap } from "app-builder-lib/out/targets/blockmap/blockmap.js";

const SIGNER = "SignPath Foundation";
const suffixes = { mac: "-mac", windows: "", linux: "-linux" };

export function feedName(version, platform) {
  // electron-builder names the feed after the first prerelease label.
  return `${/^[^-+]+-([^.+]+)/.exec(version)?.[1] ?? "latest"}${suffixes[platform]}.yml`;
}

// electron-builder writes these feeds with js-yaml in a fixed layout: top-level
// keys, then one list entry per installer under files.
function readFeed(text) {
  const feed = { files: [] };
  for (const line of text.split(/\r?\n/)) {
    const match = /^(\s*)(- )?(\w+): (.*)$/.exec(line);
    if (!match) continue;
    const [, indent, item, key, value] = match;
    if (!indent && !item) feed[key] = value;
    else {
      if (item) feed.files.push({});
      feed.files.at(-1)[key] = value;
    }
  }
  return feed;
}

async function measure(file) {
  const hash = createHash("sha512");
  let size = 0;
  for await (const bytes of createReadStream(file)) {
    hash.update(bytes);
    size += bytes.length;
  }
  return { sha512: hash.digest("base64"), size };
}

// Installed apps trust the feed's hash and size, so the feed must describe
// exactly these installers.
export async function verifyUpdateFeed(directory, version, platform, names) {
  const name = feedName(version, platform);
  let feed;
  try {
    feed = readFeed(await readFile(join(directory, name), "utf8"));
  } catch {
    throw new Error(`Missing update feed: ${name}`);
  }
  if (feed.version !== version)
    throw new Error(`The ${name} update feed does not match the package version.`);
  const urls = feed.files.map((file) => file.url).sort();
  if (urls.join("\n") !== [...names].sort().join("\n") || !names.includes(feed.path))
    throw new Error(`The ${name} update feed must list only ${names.join(" and ")}.`);
  for (const file of feed.files) {
    const actual = await measure(join(directory, file.url));
    if (file.sha512 !== actual.sha512 || Number(file.size) !== actual.size ||
        (file.url === feed.path && feed.sha512 !== actual.sha512))
      throw new Error(`The ${name} update feed does not match ${file.url}.`);
  }
}

// Returns the Authenticode certificate table that signing appends to a Windows
// executable, or null when the file is unsigned. Windows and the updater check
// the signature itself; this only shows which certificate a release carries.
async function certificates(file) {
  const bytes = await readFile(file);
  const header = bytes.readUInt32LE(0x3c);
  if (bytes.toString("latin1", header, header + 4) !== "PE\0\0")
    throw new Error(`${file} is not a Windows executable.`);
  const optional = header + 24;
  // The security entry is the fifth data directory. Its offset depends on
  // whether the optional header is PE32 or PE32+.
  const entry = optional + (bytes.readUInt16LE(optional) === 0x20b ? 112 : 96) + 4 * 8;
  const offset = bytes.readUInt32LE(entry);
  const size = bytes.readUInt32LE(entry + 4);
  return offset && size ? bytes.subarray(offset, offset + size) : null;
}

// A Windows installer without SignPath Foundation's signature must not be
// offered as an update, because installed apps would download it and then
// refuse it. Returns whether the release updates Windows installs.
export async function verifyWindowsUpdate(directory, version) {
  const installer = `Textify-${version}-win-x64.exe`;
  const name = feedName(version, "windows");
  const table = await certificates(join(directory, installer));
  if (!table) {
    if (await access(join(directory, name)).then(() => true, () => false))
      throw new Error(`Remove ${name}. Installed Windows apps accept only installers signed by ${SIGNER}.`);
    return false;
  }
  if (!table.includes(SIGNER))
    throw new Error(`${installer} must be signed by ${SIGNER}.`);
  await verifyUpdateFeed(directory, version, "windows", [installer]);
  return true;
}

// Signing changes the installer's bytes, so its blockmap and feed entry are
// rebuilt from the signed file.
export async function refreshWindowsFeed(directory, version) {
  const installer = `Textify-${version}-win-x64.exe`;
  const file = join(directory, installer);
  const table = await certificates(file);
  if (!table?.includes(SIGNER))
    throw new Error(`${installer} must be signed by ${SIGNER}.`);
  const path = join(directory, feedName(version, "windows"));
  let text = await readFile(path, "utf8");
  const entries = readFeed(text).files;
  if (entries.length !== 1 || entries[0].url !== installer)
    throw new Error(`The Windows update feed must list only ${installer}.`);
  const { sha512, size } = await buildBlockMap(file, "gzip", `${file}.blockmap`);
  text = text
    .replaceAll(entries[0].sha512, sha512)
    .replace(new RegExp(`^(\\s+size: )${entries[0].size}$`, "m"), `$1${size}`);
  await writeFile(path, text);
  await verifyUpdateFeed(directory, version, "windows", [installer]);
}
