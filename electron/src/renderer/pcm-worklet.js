class TextifyPCM extends AudioWorkletProcessor {
  constructor() {
    super();
    this.buffer = new Float32Array(320);
    this.count = 0;
    this.port.onmessage = () => {
      this.flush();
      this.port.postMessage("flushed");
    };
  }
  flush() {
    if (this.count) {
      const data = this.buffer.slice(0, this.count);
      this.port.postMessage(data.buffer, [data.buffer]);
      this.buffer.fill(0);
      this.count = 0;
    }
  }
  process(inputs) {
    const channels = inputs[0];
    if (!channels?.length) return true;
    for (let i = 0; i < channels[0].length; i++) {
      let value = 0;
      for (const channel of channels) value += channel[i];
      this.buffer[this.count++] = Math.max(
        -1,
        Math.min(1, value / channels.length),
      );
      if (this.count === this.buffer.length) this.flush();
    }
    return true;
  }
}
registerProcessor("textify-pcm", TextifyPCM);
