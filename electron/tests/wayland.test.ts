import { EventEmitter } from "node:events";
import { afterEach, describe, expect, it, vi } from "vitest";
import { waylandTrigger } from "../src/main/wayland";

const mocked = vi.hoisted(() => ({ connect: vi.fn() }));
vi.mock("@deltachat/dbus-next", () => ({
  default: {
    sessionBus: mocked.connect,
    Variant: class {
      constructor(
        public signature: string,
        public value: unknown,
      ) {}
    },
    Message: class {
      constructor(value: object) {
        Object.assign(this, value);
      }
    },
  },
}));

function desktop(options: { denied?: boolean; missing?: boolean } = {}) {
  const bus = Object.assign(new EventEmitter(), {
    name: ":1.42",
    call: vi.fn(async () => ({})),
    disconnect: vi.fn(),
    getProxyObject: vi.fn(),
  });
  const sessionPath = "/org/freedesktop/portal/desktop/session/1_42/textify";
  const session = Object.assign(new EventEmitter(), {
    Close: vi.fn(async () => {}),
  });
  const respond = (token: string, result: object) =>
    bus.emit("message", {
      path: `/org/freedesktop/portal/desktop/request/1_42/${token}`,
      interface: "org.freedesktop.portal.Request",
      member: "Response",
      body: [options.denied ? 1 : 0, result],
    });
  const portal = Object.assign(new EventEmitter(), {
    CreateSession: vi.fn(async (opts: any) => {
      // A response can arrive before the method returns its request handle.
      respond(opts.handle_token.value, {
        session_handle: { value: sessionPath },
      });
    }),
    BindShortcuts: vi.fn(
      async (_session: string, _shortcuts: any, _parent: string, opts: any) => {
        respond(opts.handle_token.value, {
          shortcuts: {
            value: [
              ["dictate", { trigger_description: { value: "Ctrl+Space" } }],
            ],
          },
        });
      },
    ),
  });
  bus.getProxyObject.mockImplementation(
    async (_destination: string, path: string) => ({
      getInterface(name: string) {
        if (path === sessionPath) return session;
        if (
          options.missing ||
          name !== "org.freedesktop.portal.GlobalShortcuts"
        )
          throw new Error("not_supported");
        return portal;
      },
    }),
  );
  mocked.connect.mockReturnValue(bus);
  const events = {
    press: vi.fn(),
    release: vi.fn(),
    cancel: vi.fn(),
    other: vi.fn(),
  };
  return { bus, portal, session, sessionPath, events };
}

afterEach(() => vi.clearAllMocks());
describe("Wayland hold shortcut protocol", () => {
  it("handles an early response and only accepts activation/release for its bound session", async () => {
    const { bus, portal, session, sessionPath, events } = desktop();
    const trigger = await waylandTrigger(events);
    expect(trigger.description).toBe("Ctrl+Space");
    portal.emit("Activated", "/other-session", "dictate");
    portal.emit("Activated", sessionPath, "other-shortcut");
    expect(events.press).not.toHaveBeenCalled();
    portal.emit("Activated", sessionPath, "dictate");
    portal.emit("Deactivated", sessionPath, "dictate");
    expect(events.press).toHaveBeenCalledOnce();
    expect(events.release).toHaveBeenCalledOnce();
    expect(bus.listenerCount("message")).toBe(0);
    expect(
      bus.call.mock.calls.filter(
        ([message]: any) => message.member === "RemoveMatch",
      ),
    ).toHaveLength(2);
    trigger.stop();
    await vi.waitFor(() => expect(bus.disconnect).toHaveBeenCalled());
    expect(session.Close).toHaveBeenCalledOnce();
  });
  it("cancels the recording when the desktop closes its session", async () => {
    const { session, bus, events } = desktop();
    await waylandTrigger(events);
    session.emit("Closed");
    expect(events.cancel).toHaveBeenCalledOnce();
    expect(bus.disconnect).toHaveBeenCalledOnce();
  });
  it("does not start recording when shortcut consent is denied", async () => {
    const { bus, events } = desktop({ denied: true });
    await expect(waylandTrigger(events)).rejects.toThrow("portal_denied");
    expect(events.press).not.toHaveBeenCalled();
    expect(bus.listenerCount("message")).toBe(0);
    expect(bus.disconnect).toHaveBeenCalledOnce();
  });
  it("disconnects when the desktop has no GlobalShortcuts portal", async () => {
    const { bus, events } = desktop({ missing: true });
    await expect(waylandTrigger(events)).rejects.toThrow("not_supported");
    expect(bus.disconnect).toHaveBeenCalledOnce();
  });
});
