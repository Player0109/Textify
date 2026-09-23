export type AccessibilityStatus = "required" | "waiting" | "granted";

/** Only the explicit request prompts. Focus checks and polling are read-only. */
export class AccessibilitySetup {
  status: AccessibilityStatus = "required";
  private timer?: ReturnType<typeof setInterval>;
  private deadline = 0;

  constructor(
    private trusted: (prompt: boolean) => boolean,
    private changed: (granted: boolean) => void,
  ) {}

  refresh() {
    const granted = this.trusted(false);
    const next = granted
      ? "granted"
      : this.timer && Date.now() < this.deadline
        ? "waiting"
        : "required";
    if (next !== "waiting") this.stop();
    if (this.status !== next) {
      this.status = next;
      this.changed(granted);
    }
    return granted;
  }

  request(prompt = true) {
    if (this.refresh()) return;
    // The native prompt is asynchronous. Its immediate false return is not denial.
    if (prompt && this.status !== "waiting") this.trusted(true);
    this.stop();
    this.deadline = Date.now() + 5 * 60_000;
    this.timer = setInterval(() => this.refresh(), 1000);
    this.status = "waiting";
    this.changed(false);
    this.refresh();
  }

  stop() {
    clearInterval(this.timer);
    this.timer = undefined;
  }
}
