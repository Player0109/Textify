#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <unistd.h>
#include <iostream>
#include <set>
#include <string>
#include <vector>
#include "platform-json.h"

static std::vector<unsigned long> property(Display *display, Window window, const char *name, Atom expected) {
    Atom type; int format; unsigned long count, remaining; unsigned char *bytes = nullptr;
    std::vector<unsigned long> result;
    if (XGetWindowProperty(display, window, XInternAtom(display, name, False), 0, 2048, False, expected, &type, &format, &count, &remaining, &bytes) == Success && type == expected && format == 32 && bytes) {
        auto *values = reinterpret_cast<unsigned long *>(bytes); result.assign(values, values + count);
    }
    if (bytes) XFree(bytes); return result;
}
static std::string executable(Display *display, Window window, unsigned long &pid) {
    const auto value = property(display, window, "_NET_WM_PID", XA_CARDINAL);
    if (value.empty()) return "";
    pid = value[0]; char path[4096];
    const auto count = readlink(("/proc/" + std::to_string(pid) + "/exe").c_str(), path, sizeof(path));
    return count > 0 && count < sizeof(path) ? std::string(path, count) : "";
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    Display *display = XOpenDisplay(nullptr); if (!display) return 2;
    // Windows may disappear while their properties are being read.
    XSetErrorHandler([](Display *, XErrorEvent *) { return 0; });
    const Window root = DefaultRootWindow(display);
    const std::string action = argv[1];
    if (action == "target") {
        const auto active = property(display, root, "_NET_ACTIVE_WINDOW", XA_WINDOW);
        const Window window = active.empty() ? 0 : active[0]; unsigned long pid = 0;
        const auto path = executable(display, window, pid);
        std::cout << "{\"target\":\"" << window << ':' << pid << "\",\"secure\":false,\"appID\":" << jsonString(path) << ",\"appName\":" << jsonString(path.substr(path.find_last_of('/') + 1)) << "}\n";
    } else if (action == "apps") {
        std::set<std::string> seen; std::cout << '['; bool first = true;
        for (auto window : property(display, root, "_NET_CLIENT_LIST", XA_WINDOW)) {
            unsigned long pid = 0; const auto path = executable(display, window, pid);
            if (path.empty() || !seen.insert(path).second || seen.size() > 200) continue;
            if (!first) std::cout << ','; first = false;
            std::cout << "{\"id\":" << jsonString(path) << ",\"name\":" << jsonString(path.substr(path.find_last_of('/') + 1)) << '}';
        }
        std::cout << "]\n";
    } else { XCloseDisplay(display); return 2; }
    XCloseDisplay(display); return 0;
}
