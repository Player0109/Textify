import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

// Seconds of likely speech in a recording, from the Silero speech detector
// (textify-whisper --speech <model>). It runs on the CPU in a short-lived
// process; PCM enters through stdin and is never logged.
export function speechSeconds(
  command: string,
  args: string[],
  samples: Float32Array,
): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: "pipe",
      windowsHide: true,
      shell: false,
    });
    const timer = setTimeout(() => child.kill(), 10000);
    const lines: string[] = [];
    createInterface({ input: child.stdout }).on("line", (line) =>
      lines.push(line),
    );
    child.stderr.resume(); // Native diagnostics are never forwarded or retained.
    child.stdin.on("error", () => {});
    child.on("error", () => reject(new Error("speech_check")));
    child.on("close", () => {
      clearTimeout(timer);
      try {
        const [ready, result] = lines.map((line) => JSON.parse(line));
        if (
          lines.length === 2 &&
          ready.ready === true &&
          Number.isFinite(result.speech) &&
          result.speech >= 0
        )
          return resolve(result.speech);
      } catch {}
      reject(new Error("speech_check"));
    });
    const header = Buffer.alloc(4);
    header.writeUInt32LE(samples.length);
    const audio = Buffer.alloc(samples.length * 4);
    for (let i = 0; i < samples.length; i++)
      audio.writeFloatLE(samples[i], i * 4);
    child.stdin.write(header);
    child.stdin.end(audio, () => audio.fill(0));
  });
}
