export type Phase =
  | "idle"
  | "armed"
  | "recording"
  | "processing"
  | "inserting"
  | "copy"
  | "error";
export type Trigger =
  | "right-command"
  | "right-option"
  | "right-control"
  | "control-space";
export interface Replacement {
  trigger: string;
  replacement: string;
}
export interface Preferences {
  microphone: string;
  trigger: Trigger;
  replacements: Replacement[];
  customWords: string[];
  language: string;
  activeModelID: string;
  launchAtLogin: boolean;
  exclusions: { id: string; name: string }[];
  overlay: { x: number; y: number; scale: number };
}
export interface ModelView {
  id: string;
  name: string;
  bytes: number;
  installed: boolean;
  status: "installed" | "not-installed" | "revoked" | "verify-required";
  languages: string[];
  resumable: boolean;
  storedBytes: number;
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
  gpu: { backend: "Metal" | "Vulkan"; device: string } | null;
  modelBusy: boolean;
  download: number | null;
  downloadModelID: string | null;
  exclusionsAvailable: boolean;
  startupAvailable: boolean;
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
export type ModelCommand = {
  action: "download" | "import" | "use" | "verify" | "remove";
  id: string;
};
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
  model(command: ModelCommand): Promise<void>;
  apps(): Promise<{ id: string; name: string }[]>;
  importSettings(): Promise<{
    preferences: Preferences;
    notes: string[];
  } | null>;
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

export const LANGUAGES: Record<string, string> = {
  en: "English",
  hi: "Hindi",
  es: "Spanish",
  fr: "French",
  de: "German",
  it: "Italian",
  pt: "Portuguese",
  nl: "Dutch",
  pl: "Polish",
  cs: "Czech",
  sk: "Slovak",
  sl: "Slovenian",
  hr: "Croatian",
  bs: "Bosnian",
  ro: "Romanian",
  da: "Danish",
  sv: "Swedish",
  fi: "Finnish",
  hu: "Hungarian",
  et: "Estonian",
  lv: "Latvian",
  lt: "Lithuanian",
  mt: "Maltese",
  ru: "Russian",
  uk: "Ukrainian",
  be: "Belarusian",
  bg: "Bulgarian",
  sr: "Serbian",
  el: "Greek",
  zh: "Chinese",
  yue: "Cantonese",
  ja: "Japanese",
  ko: "Korean",
  ar: "Arabic",
};
