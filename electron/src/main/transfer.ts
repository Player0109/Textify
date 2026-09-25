import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import {
  open,
  readFile,
  rename,
  rm,
  stat,
  truncate,
  writeFile,
} from "node:fs/promises";

export interface ModelFile {
  filename: string;
  url: string;
  sha256: string;
  sizeBytes: number;
}
export async function hashFile(path: string) {
  const hash = createHash("sha256");
  for await (const bytes of createReadStream(path)) hash.update(bytes);
  return hash.digest("hex");
}
export async function validFile(path: string, file: ModelFile) {
  try {
    return (
      (await stat(path)).size === file.sizeBytes &&
      (await hashFile(path)) === file.sha256
    );
  } catch {
    return false;
  }
}
export async function transfer(
  file: ModelFile,
  destination: string,
  signal: AbortSignal,
  progress: (value: number) => void,
  source?: string,
) {
  const partial = `${destination}.partial`,
    metadata = `${partial}.json`;
  const clear = async () => {
    await rm(partial, { force: true });
    await rm(metadata, { force: true });
  };
  if (source) {
    if ((await stat(source)).size !== file.sizeBytes)
      throw new Error("model_integrity");
    const output = await open(partial, "w", 0o600);
    try {
      let received = 0;
      for await (const bytes of createReadStream(source)) {
        signal.throwIfAborted();
        received += bytes.length;
        if (received > file.sizeBytes) throw new Error("download_size");
        await output.writeFile(bytes);
        progress(received / file.sizeBytes);
      }
      await output.sync();
    } catch (error) {
      await output.close();
      await clear();
      throw error;
    }
    await output.close();
  } else if (!(await validFile(partial, file))) {
    let received = 0,
      etag: string | null = null;
    const hash = createHash("sha256");
    try {
      const saved = JSON.parse(await readFile(metadata, "utf8"));
      if (
        saved.url !== file.url ||
        saved.sha256 !== file.sha256 ||
        saved.sizeBytes !== file.sizeBytes ||
        !Number.isSafeInteger(saved.received) ||
        saved.received <= 0 ||
        saved.received >= file.sizeBytes ||
        (await stat(partial)).size < saved.received
      )
        throw new Error("resume_stale");
      await truncate(partial, saved.received);
      if ((await hashFile(partial)) !== saved.prefixSHA256)
        throw new Error("resume_corrupt");
      for await (const bytes of createReadStream(partial)) hash.update(bytes);
      received = saved.received;
      etag =
        typeof saved.etag === "string" && /^"[^\r\n]+"$/.test(saved.etag)
          ? saved.etag
          : null;
    } catch {
      await clear();
    }
    const headers: Record<string, string> = {};
    if (received) {
      headers.Range = `bytes=${received}-`;
      if (etag) headers["If-Range"] = etag;
    }
    const response = await fetch(file.url, { signal, headers });
    if (!response.ok || !response.body || ![200, 206].includes(response.status))
      throw new Error("download_failed");
    if (received && response.status === 200) {
      received = 0;
      etag = null;
    }
    if (response.status === 206) {
      const range = response.headers
        .get("content-range")
        ?.match(/^bytes (\d+)-(\d+)\/(\d+)$/);
      if (
        !range ||
        Number(range[1]) !== received ||
        Number(range[2]) !== file.sizeBytes - 1 ||
        Number(range[3]) !== file.sizeBytes
      ) {
        await response.body.cancel();
        throw new Error("download_range");
      }
    }
    // A full restart uses a fresh hash even when a previous prefix was valid.
    const digest = received ? hash : createHash("sha256");
    etag = response.headers.get("etag");
    const output = await open(partial, received ? "a" : "w", 0o600);
    let checkpoint = received;
    const save = async () => {
      await output.sync();
      await writeFile(
        `${metadata}.tmp`,
        JSON.stringify({
          ...file,
          received,
          prefixSHA256: digest.copy().digest("hex"),
          etag,
        }),
        { mode: 0o600 },
      );
      await rename(`${metadata}.tmp`, metadata);
      checkpoint = received;
    };
    try {
      for await (const bytes of response.body) {
        signal.throwIfAborted();
        if (received + bytes.length > file.sizeBytes)
          throw new Error("download_size");
        await output.writeFile(bytes);
        received += bytes.length;
        digest.update(bytes);
        progress(received / file.sizeBytes);
        if (received - checkpoint >= 4 * 1024 * 1024) await save();
      }
      await save();
      if (received !== file.sizeBytes) throw new Error("download_incomplete");
    } catch (error: any) {
      if (error.message === "download_size") {
        await output.close();
        await clear();
        throw error;
      }
      await save();
      throw error;
    } finally {
      await output.close().catch(() => {});
    }
  }
  signal.throwIfAborted();
  if (!(await validFile(partial, file))) {
    await clear();
    throw new Error("model_integrity");
  }
  // The caller owns the final admission and atomic rename after checking revocation.
  return partial;
}
