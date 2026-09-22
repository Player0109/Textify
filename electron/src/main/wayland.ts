import dbus from "@deltachat/dbus-next";
import { randomBytes } from "node:crypto";
import type { TriggerEvents } from "./platform";

// Electron globalShortcut exposes activation only. Hold-to-record requires both
// signals from the portal, so use its session directly on Wayland.
export async function waylandTrigger(
  events: TriggerEvents,
): Promise<{ stop(): void; description: string }> {
  const bus = dbus.sessionBus();
  bus.on("error", () => events.cancel());
  const destination = "org.freedesktop.portal.Desktop";
  let root, portal;
  try {
    root = await bus.getProxyObject(
      destination,
      "/org/freedesktop/portal/desktop",
    );
    portal = root.getInterface("org.freedesktop.portal.GlobalShortcuts");
  } catch (error) {
    bus.disconnect();
    throw error;
  }
  const variant = (value: string) => new dbus.Variant("s", value);
  async function request(
    invoke: (token: string) => Promise<unknown>,
  ): Promise<any> {
    const token = `textify_${randomBytes(8).toString("hex")}`;
    const uniqueName = (bus as typeof bus & { name: string }).name;
    const path = `/org/freedesktop/portal/desktop/request/${uniqueName.slice(1).replace(/\./g, "_")}/${token}`;
    const rule = `type='signal',interface='org.freedesktop.portal.Request',member='Response',path='${path}'`;
    await bus.call(
      new dbus.Message({
        destination: "org.freedesktop.DBus",
        path: "/org/freedesktop/DBus",
        interface: "org.freedesktop.DBus",
        member: "AddMatch",
        signature: "s",
        body: [rule],
      }),
    );
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timer);
        bus.off("message", listener);
        void bus
          .call(
            new dbus.Message({
              destination: "org.freedesktop.DBus",
              path: "/org/freedesktop/DBus",
              interface: "org.freedesktop.DBus",
              member: "RemoveMatch",
              signature: "s",
              body: [rule],
            }),
          )
          .catch(() => {});
      };
      const listener = (message: dbus.Message) => {
        if (
          message.path !== path ||
          message.interface !== "org.freedesktop.portal.Request" ||
          message.member !== "Response"
        )
          return;
        cleanup();
        const [code, result] = message.body;
        if (code === 0) resolve(result);
        else reject(new Error("portal_denied"));
      };
      const timer = setTimeout(() => {
        cleanup();
        reject(new Error("portal_timeout"));
      }, 120000);
      bus.on("message", listener);
      invoke(token).catch(() => {
        cleanup();
        reject(new Error("portal_unavailable"));
      });
    });
  }
  try {
    // Register host identity when the portal offers the Registry interface.
    try {
      await root
        .getInterface("org.freedesktop.host.portal.Registry")
        .Register("io.github.Player0109.Textify.Electron", {});
    } catch {
      /* Installed desktop identity may already be available. */
    }
    const created = await request((token) =>
      portal.CreateSession({
        handle_token: variant(token),
        session_handle_token: variant(`${token}_session`),
      }),
    );
    const session = created.session_handle?.value;
    if (typeof session !== "string") throw new Error("portal_session");
    portal.on("Activated", (handle: string, id: string) => {
      if (handle === session && id === "dictate") events.press();
    });
    portal.on("Deactivated", (handle: string, id: string) => {
      if (handle === session && id === "dictate") events.release();
    });
    const bound = await request((token) =>
      portal.BindShortcuts(
        session,
        [
          [
            "dictate",
            {
              description: variant("Hold to dictate with Textify"),
              preferred_trigger: variant("CTRL+space"),
            },
          ],
        ],
        "",
        { handle_token: variant(token) },
      ),
    );
    const shortcut = bound.shortcuts?.value?.find(
      (row: any[]) => row[0] === "dictate",
    );
    if (!shortcut) throw new Error("portal_unbound");
    const sessionObject = await bus.getProxyObject(destination, session);
    const sessionInterface = sessionObject.getInterface(
      "org.freedesktop.portal.Session",
    );
    sessionInterface.on("Closed", () => {
      events.cancel();
      bus.disconnect();
    });
    return {
      description: shortcut[1].trigger_description?.value || "Desktop shortcut",
      stop() {
        void sessionInterface
          .Close()
          .catch(() => {})
          .finally(() => bus.disconnect());
      },
    };
  } catch (error) {
    bus.disconnect();
    throw error;
  }
}
