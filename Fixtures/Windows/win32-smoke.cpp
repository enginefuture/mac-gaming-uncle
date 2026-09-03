#include <windows.h>

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_KEYDOWN && wparam == VK_ESCAPE) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    if (message == WM_PAINT) {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT bounds{}; GetClientRect(window, &bounds);
        FillRect(dc, &bounds, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));
        SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(20, 90, 180));
        HFONT font = CreateFontW(28, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Tahoma");
        HGDIOBJ previous = SelectObject(dc, font);
        DrawTextW(dc, L"中文字体测试：Windows 游戏可以显示中文 — 按 Esc 退出", -1, &bounds, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(dc, previous); DeleteObject(font);
        EndPaint(window, &paint);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    WNDCLASSW klass{}; klass.lpfnWndProc = WindowProc; klass.hInstance = instance;
    klass.lpszClassName = L"IndieSmokeFixture"; klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&klass)) return 10;
    HWND window = CreateWindowExW(0, klass.lpszClassName, L"Indie 兼容性测试 — 中文字体", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 800, 450, nullptr, nullptr, instance, nullptr);
    if (!window) return 11;
    ShowWindow(window, show);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    return static_cast<int>(message.wParam);
}
