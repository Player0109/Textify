#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <oleauto.h>
#include <initguid.h>
#include <UIAutomation.h>
#include <iostream>
#include <string>
#include <vector>
#include <cstdint>
#include <cstring>

static std::string target() {
    HWND window = GetForegroundWindow();
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    return std::to_string(reinterpret_cast<uintptr_t>(window)) + ":" + std::to_string(pid);
}
static bool secure() {
    IUIAutomation *automation = nullptr;
    IUIAutomationElement *field = nullptr;
    BOOL password = FALSE;
    if (SUCCEEDED(CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation)))) {
        if (SUCCEEDED(automation->GetFocusedElement(&field)) && field) {
            field->get_CurrentIsPassword(&password);
            field->Release();
        }
        automation->Release();
    }
    return password == TRUE;
}
struct Format { UINT id; HGLOBAL data; };
static void release(std::vector<Format> &items) { for (auto &item : items) if (item.data) GlobalFree(item.data); }
int main(int argc, char **argv) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (argc == 2 && std::string(argv[1]) == "target") {
        std::cout << "{\"target\":\"" << target() << "\",\"secure\":" << (secure() ? "true" : "false") << "}\n";
        return 0;
    }
    if (argc != 3 || std::string(argv[1]) != "paste") return 2;
    std::string input((std::istreambuf_iterator<char>(std::cin)), {});
    if (input.empty() || input.size() > 65536) return 2;
    auto matches = [&] { return target() == argv[2] && !secure(); };
    if (!matches()) { std::cout << "{\"status\":\"skipped\"}\n"; return 0; }
    HWND owner = CreateWindowExW(0, L"STATIC", L"Textify", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, GetModuleHandle(nullptr), nullptr);
    if (!owner || !OpenClipboard(owner)) { std::cout << "{\"status\":\"unavailable\"}\n"; return 0; }
    std::vector<Format> snapshot;
    bool safe = true;
    size_t total = 0;
    for (UINT format = EnumClipboardFormats(0); format; format = EnumClipboardFormats(format)) {
        // These formats are object handles, not HGLOBAL byte buffers.
        if (format == CF_BITMAP || format == CF_METAFILEPICT || format == CF_ENHMETAFILE || format == CF_PALETTE ||
            (format >= CF_GDIOBJFIRST && format <= CF_GDIOBJLAST)) { safe = false; break; }
        HANDLE original = GetClipboardData(format);
        SIZE_T size = original ? GlobalSize(original) : 0;
        if (!size || (total += size) > 64 * 1024 * 1024) { safe = false; break; }
        void *source = GlobalLock(original);
        HGLOBAL copy = GlobalAlloc(GMEM_MOVEABLE, size);
        void *dest = copy ? GlobalLock(copy) : nullptr;
        if (!source || !dest) { if (source) GlobalUnlock(original); if (copy) GlobalFree(copy); safe = false; break; }
        memcpy(dest, source, size);
        GlobalUnlock(original); GlobalUnlock(copy);
        snapshot.push_back({format, copy});
    }
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), int(input.size()), nullptr, 0);
    HGLOBAL buffer = length ? GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, (length + 1) * sizeof(wchar_t)) : nullptr;
    if (!safe || !buffer || !matches()) {
        if (buffer) GlobalFree(buffer);
        release(snapshot); CloseClipboard(); DestroyWindow(owner);
        std::cout << "{\"status\":\"unavailable\"}\n"; return 0;
    }
    auto *wide = static_cast<wchar_t *>(GlobalLock(buffer));
    if (!wide) { GlobalFree(buffer); release(snapshot); CloseClipboard(); return 2; }
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), int(input.size()), wide, length);
    GlobalUnlock(buffer);
    EmptyClipboard();
    bool written = SetClipboardData(CF_UNICODETEXT, buffer) != nullptr;
    if (!written) GlobalFree(buffer);
    if (written) {
        // Best-effort Windows clipboard-history/cloud exclusions.
        for (const auto *name : {L"CanIncludeInClipboardHistory", L"CanUploadToCloudClipboard", L"ExcludeClipboardContentFromMonitorProcessing"}) {
            const UINT format = RegisterClipboardFormatW(name);
            HGLOBAL marker = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DWORD));
            if (marker && (!format || !SetClipboardData(format, marker))) GlobalFree(marker);
        }
    }
    CloseClipboard();
    DWORD version = GetClipboardSequenceNumber();
    UINT sent = 0;
    if (written && matches()) {
        INPUT keys[4] = {};
        for (auto &key : keys) key.type = INPUT_KEYBOARD;
        keys[0].ki.wVk = VK_CONTROL; keys[1].ki.wVk = 'V';
        keys[2].ki.wVk = 'V'; keys[2].ki.dwFlags = KEYEVENTF_KEYUP;
        keys[3].ki.wVk = VK_CONTROL; keys[3].ki.dwFlags = KEYEVENTF_KEYUP;
        sent = SendInput(4, keys, sizeof(INPUT));
        Sleep(200);
    }
    if (GetClipboardSequenceNumber() == version && OpenClipboard(owner)) {
        if (GetClipboardSequenceNumber() == version) {
            EmptyClipboard();
            for (auto &item : snapshot) if (SetClipboardData(item.id, item.data)) item.data = nullptr;
        }
        CloseClipboard();
    }
    release(snapshot); DestroyWindow(owner);
    // Any posted input precludes retrying: a partial or delayed paste is unobservable.
    std::cout << "{\"status\":\"" << (sent ? "sent" : "skipped") << "\"}\n";
    CoUninitialize();
}
