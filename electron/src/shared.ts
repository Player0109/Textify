export type Phase =
  | "idle"
  | "armed"
  | "recording"
  | "processing"
  | "inserting"
  | "copy"
  | "error";
export type Trigger = "right-command" | "right-control" | "control-space";
export interface Replacement {
  trigger: string;
  replacement: string;
}
export interface Preferences {
  microphone: string;
  trigger: Trigger;
  replacements: Replacement[];
}
export interface ModelView {
  id: string;
  name: string;
  bytes: number;
  installed: boolean;
}
export interface Snapshot {
  phase: Phase;
  message: string;
  level: number;
  elapsed: number;
  platform: string;
  triggerStatus: string;
  insertion: "automatic" | "copy";
  ready: boolean;
  modelBusy: boolean;
  download: number | null;
  preferences: Preferences;
  models: ModelView[];
}
export type Action =
  | "press"
  | "release"
  | "cancel"
  | "copy"
  | "dismiss"
  | "microphone"
  | "permissions"
  | "enable-trigger"
  | "download"
  | "cancel-download"
  | "import";
export type AudioCommand = {
  id: number;
  action: "start" | "stop" | "discard" | "probe";
  microphone?: string;
};
export type AudioReply = {
  id: number;
  kind: "started" | "stopped" | "error" | "devices" | "samples";
  samples?: ArrayBuffer;
  devices?: { id: string; name: string }[];
};
export interface TextifyBridge {
  snapshot(): Promise<Snapshot>;
  action(action: Action): Promise<void>;
  preferences(value: Preferences): Promise<void>;
  subscribe(callback: (state: Snapshot) => void): () => void;
  audioListen(callback: (command: AudioCommand) => void): () => void;
  audioReply(reply: AudioReply): void;
  devices(): Promise<{ id: string; name: string }[]>;
}
declare global {
  interface Window {
    textify: TextifyBridge;
  }
}
