import type { Replacement } from "../shared";
const commands: [string, string, string][] = [
  ["exclamation mark|exclamation point", "!", "attach"],
  ["question mark", "?", "attach"],
  ["new paragraph", "\n\n", "strip"],
  ["new line", "\n", "strip"],
  ["open parenthesis|open paren", "(", "open"],
  ["close parenthesis|close paren", ")", "attach"],
  ["open quote", '"', "open"],
  ["close quote", '"', "attach"],
  ["forward slash", "/", "strip"],
  ["backslash", "\\", "strip"],
  ["at sign", "@", "strip"],
  ["full stop|period", ".", "attach"],
  ["comma", ",", "attach"],
  ["colon", ":", "attach"],
  ["semicolon", ";", "attach"],
  ["hyphen", "-", "strip"],
  ["ampersand", "&", "space"],
];
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const normalize = (s: string) =>
  s
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/ +([,.!?;:)])/g, "$1");
export function processText(
  raw: string,
  replacements: Replacement[] = [],
): string {
  const words = raw.trim().split(/\s+/);
  let text = "",
    joined = false;
  for (let i = 0; i < words.length; ) {
    let match: { count: number; value: string; space: string } | undefined;
    for (const [phrases, value, space] of commands) {
      for (const phrase of phrases.split("|")) {
        const parts = phrase.split(" ");
        if (
          words
            .slice(i, i + parts.length)
            .map((w) => w.replace(/^\p{P}+|\p{P}+$/gu, "").toLowerCase())
            .join(" ") === phrase
        ) {
          match = { count: parts.length, value, space };
          break;
        }
      }
      if (match) break;
    }
    if (match) {
      if (match.space === "attach" || match.space === "strip")
        text = text.trimEnd();
      else if (text && !/\s$/.test(text)) text += " ";
      text += match.value;
      joined = match.space === "open" || match.space === "strip";
      if (match.space === "space") text += " ";
      i += match.count;
    } else {
      if (text && !/\s$/.test(text) && !joined) text += " ";
      text += words[i++];
      joined = false;
    }
  }
  text = normalize(
    text
      .replace(/([,.;:!?])(?:\s*\1)+/g, "$1")
      .replace(/\b(?:um|uh|you\s+know)\b[, ]*/gi, "")
      .replace(/(^|[.!?,;:]\s+)like,?\s+/gi, "$1"),
  ).trim();
  let segments = [{ text, protected: false }];
  for (const pair of [...replacements].sort(
    (a, b) => b.trigger.length - a.trigger.length,
  )) {
    if (!pair.trigger.trim()) continue;
    const pattern = new RegExp(
      `(?<![\\p{L}\\p{N}_])${pair.trigger.trim().split(/\s+/).map(escape).join("\\s+")}(?![\\p{L}\\p{N}_])`,
      "giu",
    );
    segments = segments.flatMap((segment) => {
      if (segment.protected) return [segment];
      const result = [];
      let end = 0;
      for (const match of segment.text.matchAll(pattern)) {
        result.push(
          { text: segment.text.slice(end, match.index), protected: false },
          { text: pair.replacement, protected: true },
        );
        end = match.index + match[0].length;
      }
      result.push({ text: segment.text.slice(end), protected: false });
      return result;
    });
  }
  let sentenceStart = true;
  return segments
    .map((segment) => {
      if (segment.protected) {
        for (const ch of segment.text) {
          if (/[.!?\n]/.test(ch)) sentenceStart = true;
          else if (/\p{L}/u.test(ch)) sentenceStart = false;
        }
        return segment.text;
      }
      return segment.text
        .replace(/\bi\b/g, "I")
        .split("")
        .map((ch) => {
          if (/[.!?\n]/.test(ch)) sentenceStart = true;
          else if (/\p{L}/u.test(ch)) {
            const value = sentenceStart ? ch.toUpperCase() : ch;
            sentenceStart = false;
            return value;
          }
          return ch;
        })
        .join("");
    })
    .join("");
}
