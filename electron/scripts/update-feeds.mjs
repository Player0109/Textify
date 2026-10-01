import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

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
