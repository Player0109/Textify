import { contextBridge, ipcRenderer } from "electron";
import type { TextifyBridge } from "../shared";
const bridge: TextifyBridge = {
  snapshot: () => ipcRenderer.invoke("snapshot"),
  action: (action) => ipcRenderer.invoke("action", action),
  preferences: (value) => ipcRenderer.invoke("preferences", value),
  model: (command) => ipcRenderer.invoke("model", command),
  apps: () => ipcRenderer.invoke("apps"),
  devices: () => ipcRenderer.invoke("devices"),
  subscribe(callback) {
    const listener = (_event: unknown, state: Parameters<typeof callback>[0]) =>
      callback(state);
    ipcRenderer.on("snapshot", listener);
    return () => ipcRenderer.off("snapshot", listener);
  },
  audioListen(callback) {
    const listener = (
      _event: unknown,
      command: Parameters<typeof callback>[0],
    ) => callback(command);
    ipcRenderer.on("audio-command", listener);
    return () => ipcRenderer.off("audio-command", listener);
  },
  audioReply: (reply) => ipcRenderer.send("audio-reply", reply),
  accessibilityHelp: (command) => ipcRenderer.send("accessibility-help", command),
};
contextBridge.exposeInMainWorld("textify", bridge);
