import type { AudioCommand, AudioReply } from "../shared";
const reply = (value: AudioReply) => window.textify.audioReply(value);
let active:
  | {
      id: number;
      stream: MediaStream;
      context: AudioContext;
      node: AudioWorkletNode;
    }
  | undefined;
let chain = Promise.resolve();
let discardID: number | undefined;
async function close() {
  if (!active) return;
  const current = active;
  active = undefined;
  current.node.disconnect();
  current.stream.getTracks().forEach((track) => track.stop());
  if (current.context.state !== "closed") await current.context.close();
}
async function handle(command: AudioCommand) {
  if (command.action === "probe") {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((track) => track.stop());
    const devices = (await navigator.mediaDevices.enumerateDevices())
      .filter((d) => d.kind === "audioinput")
      .map((d) => ({ id: d.deviceId, name: d.label || "Microphone" }));
    reply({ id: command.id, kind: "devices", devices });
    return;
  }
  if (command.action === "start") {
    await close();
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        ...(command.microphone && command.microphone !== "default"
          ? { deviceId: { exact: command.microphone } }
          : {}),
      },
    });
    if (discardID === command.id) {
      stream.getTracks().forEach((track) => track.stop());
      throw new Error("cancelled");
    }
    let context: AudioContext | undefined;
    try {
      context = new AudioContext({ sampleRate: 16000 });
      if (context.sampleRate !== 16000)
        throw new Error("unsupported_sample_rate");
      await context.audioWorklet.addModule(
        new URL("./pcm-worklet.js", import.meta.url),
      );
      const node = new AudioWorkletNode(context, "textify-pcm");
      const source = context.createMediaStreamSource(stream);
      node.port.onmessage = (event) => {
        if (event.data instanceof ArrayBuffer)
          reply({ id: command.id, kind: "samples", samples: event.data });
      };
      source.connect(node);
      node.connect(context.destination);
      active = { id: command.id, stream, context, node };
      stream.getAudioTracks()[0].onended = () => {
        if (active?.id === command.id) {
          void close();
          reply({ id: command.id, kind: "error" });
        }
      };
      await context.resume();
      reply({ id: command.id, kind: "started" });
    } catch (error) {
      stream.getTracks().forEach((track) => track.stop());
      await context?.close().catch(() => {});
      throw error;
    }
    return;
  }
  if (active?.id === command.id) {
    try {
      if (command.action === "stop") {
        const node = active.node;
        await new Promise<void>((resolve, reject) => {
          const cleanup = () => {
            clearTimeout(timer);
            node.port.removeEventListener("message", handler);
          };
          const handler = (event: MessageEvent) => {
            if (event.data === "flushed") {
              cleanup();
              resolve();
            }
          };
          const timer = setTimeout(() => {
            cleanup();
            reject(new Error("audio_flush_timeout"));
          }, 1000);
          node.port.addEventListener("message", handler);
          node.port.postMessage("flush");
        });
      }
    } finally {
      await close();
    }
  }
  reply({ id: command.id, kind: "stopped" });
}
export function startAudioRenderer() {
  window.textify.audioListen((command) => {
    if (command.action === "discard") discardID = command.id;
    chain = chain
      .then(() => handle(command))
      .catch(() => {
        reply({ id: command.id, kind: "error" });
      });
  });
}
