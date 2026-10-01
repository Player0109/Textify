// Word-level comparison of transcripts from different models. Case and
// punctuation are ignored, so only heard words count as differences.

export type Token = { text: string; word: string };

export function tokens(text: string): Token[] {
  return text
    .split(/\s+/)
    .filter(Boolean)
    .map((text) => ({
      text,
      word: text
        .normalize("NFKC")
        .toLowerCase()
        .replace(/[‘’]/g, "'")
        .replace(/[^\p{L}\p{N}']+/gu, "")
        .replace(/^'+|'+$/g, ""),
    }));
}

// Aligns the words of two transcripts with the fewest edits and marks, for
// each token of each side, whether it has no matching word on the other side.
export function differences(a: string, b: string) {
  const x = tokens(a),
    y = tokens(b);
  const xi = x.flatMap((token, i) => (token.word ? [i] : []));
  const yi = y.flatMap((token, i) => (token.word ? [i] : []));
  const same = (i: number, j: number) => x[xi[i]].word === y[yi[j]].word;
  const cost = Array.from({ length: xi.length + 1 }, (_, i) => {
    const row = new Uint32Array(yi.length + 1);
    row[0] = i;
    return row;
  });
  for (let j = 0; j <= yi.length; j++) cost[0][j] = j;
  for (let i = 1; i <= xi.length; i++)
    for (let j = 1; j <= yi.length; j++)
      cost[i][j] = Math.min(
        cost[i - 1][j] + 1,
        cost[i][j - 1] + 1,
        cost[i - 1][j - 1] + (same(i - 1, j - 1) ? 0 : 1),
      );
  const left = x.map(() => false),
    right = y.map(() => false);
  let i = xi.length,
    j = yi.length;
  while (i > 0 || j > 0) {
    if (
      i > 0 &&
      j > 0 &&
      cost[i][j] === cost[i - 1][j - 1] + (same(i - 1, j - 1) ? 0 : 1)
    ) {
      if (!same(i - 1, j - 1)) left[xi[i - 1]] = right[yi[j - 1]] = true;
      i--;
      j--;
    } else if (i > 0 && cost[i][j] === cost[i - 1][j] + 1) {
      left[xi[--i]] = true;
    } else {
      right[yi[--j]] = true;
    }
  }
  return { left, right, edits: cost[xi.length][yi.length] };
}

// Mean word error rate of the dictation against each other model's text;
// undefined until another model has transcribed the clip.
export function disagreement(text: string, others: string[]) {
  if (!others.length) return undefined;
  const words = Math.max(1, tokens(text).filter((token) => token.word).length);
  return (
    others.reduce((total, other) => total + differences(text, other).edits, 0) /
    others.length /
    words
  );
}
