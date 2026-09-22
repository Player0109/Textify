import { mkdir, readFile, rm, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";
export function desktopEntry(executable: string) {
  if (!executable.startsWith("/") || /[\r\n\0]/.test(executable))
    throw new Error("startup_path");
  const escaped = executable
    .replace(/\\/g, "\\\\\\\\")
    .replace(/["`$]/g, "\\\\$&")
    .replace(/%/g, "%%");
  return `[Desktop Entry]\nType=Application\nName=Textify Electron\nExec="${escaped}" --background\nTerminal=false\nX-GNOME-Autostart-enabled=true\n`;
}
export async function linuxStartup(
  config: string,
  executable: string,
  enabled: boolean,
) {
  const directory = join(config, "autostart"),
    path = join(directory, "io.github.Player0109.Textify.Electron.desktop");
  if (!enabled) {
    await rm(path, { force: true });
    return;
  }
  await mkdir(directory, { recursive: true });
  await writeFile(`${path}.tmp`, desktopEntry(executable), { mode: 0o600 });
  await rename(`${path}.tmp`, path);
}
export async function linuxStartupEnabled(config: string) {
  try {
    return (
      await readFile(
        join(config, "autostart/io.github.Player0109.Textify.Electron.desktop"),
        "utf8",
      )
    ).includes("X-GNOME-Autostart-enabled=true");
  } catch {
    return false;
  }
}
