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
export type ModelEngine = "whisper_cpp" | "transcribe_cpp" | "audio_cpp";
export interface ModelView {
  directory: boolean;
  engine: ModelEngine;
  checkpointID: string;
  description: string;
  variant: string;
  provider: string;
  license: string;
  source: string;
  vocabulary: boolean;
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
  preview: string;
  application: string;
  applicationIcon: string;
  platform: string;
  triggerStatus: string;
  triggerEnabled: boolean;
  accessibility: {
    status: "required" | "waiting" | "granted";
    appName: string;
    appPath: string;
  } | null;
  insertion: "automatic" | "copy";
  ready: boolean;
  gpu: { backend: "Metal" | "Vulkan"; device: string } | null;
  modelBusy: boolean;
  // A download, import, verification or removal; excludes worker loading.
  modelStorageBusy: boolean;
  download: number | null;
  downloadModelID: string | null;
  exclusionsAvailable: boolean;
  startupAvailable: boolean;
  preferences: Preferences;
  models: ModelView[];
}
export interface ActivityTotals {
  words: number;
  dictations: number;
  recordingSeconds: number;
  estimatedTimeSavedSeconds: number;
}
export interface ActivityDay extends ActivityTotals {
  date: string;
}
export interface ActivitySnapshot {
  totals: ActivityTotals;
  days: ActivityDay[];
}
export type Action =
  | "press"
  | "release"
  | "cancel"
  | "copy"
  | "dismiss"
  | "microphone"
  | "permissions"
  | "permission-settings"
  | "reveal-app"
  | "enable-trigger"
  | "download"
  | "cancel-download"
  | "import";
export type ModelCommand = {
  action: "download" | "import" | "use" | "verify" | "remove" | "source";
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
  activity(): Promise<ActivitySnapshot>;
  action(action: Action): Promise<void>;
  preferences(value: Preferences): Promise<void>;
  model(command: ModelCommand): Promise<void>;
  apps(): Promise<{ id: string; name: string }[]>;
  subscribe(callback: (state: Snapshot) => void): () => void;
  audioListen(callback: (command: AudioCommand) => void): () => void;
  audioReply(reply: AudioReply): void;
  devices(): Promise<{ id: string; name: string }[]>;
  accessibilityHelp(command: "drag" | "dismiss" | "reveal"): void;
}
declare global {
  interface Window {
    textify: TextifyBridge;
  }
}

export const LANGUAGES: Record<string, string> = {
  auto: "Auto-detect language",
  id: "Indonesian",
  th: "Thai",
  vi: "Vietnamese",
  tr: "Turkish",
  ms: "Malay",
  fil: "Filipino",
  fa: "Persian",
  mk: "Macedonian",
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
