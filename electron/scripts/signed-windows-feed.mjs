import { readFile } from "node:fs/promises";
import { refreshWindowsFeed } from "./update-feeds.mjs";

// CI runs this after SignPath returns the signed installer.
const { version } = JSON.parse(await readFile("package.json", "utf8"));
await refreshWindowsFeed("release", version);
console.log("The Windows update feed and blockmap now describe the signed installer.");
