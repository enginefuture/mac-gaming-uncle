#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>
#include <cmath>

using Microsoft::WRL::ComPtr;

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_KEYDOWN && wparam == VK_ESCAPE) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    WNDCLASSW klass{}; klass.lpfnWndProc = WindowProc; klass.hInstance = instance;
    klass.lpszClassName = L"IndieD3D11Fixture"; klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&klass)) return 10;
    HWND window = CreateWindowExW(0, klass.lpszClassName, L"Indie Compatibility Lab — Direct3D 11", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 1280, 720, nullptr, nullptr, instance, nullptr);
    if (!window) return 11;

    DXGI_SWAP_CHAIN_DESC swap{};
    swap.BufferDesc.Width = 1280; swap.BufferDesc.Height = 720; swap.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swap.SampleDesc.Count = 1; swap.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; swap.BufferCount = 2;
    swap.OutputWindow = window; swap.Windowed = TRUE; swap.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context; ComPtr<IDXGISwapChain> chain;
    D3D_FEATURE_LEVEL level{};
    HRESULT result = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
        D3D11_SDK_VERSION, &swap, &chain, &device, &level, &context);
    if (FAILED(result)) { MessageBoxW(window, L"D3D11CreateDeviceAndSwapChain failed", L"Indie", MB_ICONERROR); return 20; }
    ComPtr<ID3D11Texture2D> buffer; ComPtr<ID3D11RenderTargetView> target;
    if (FAILED(chain->GetBuffer(0, IID_PPV_ARGS(&buffer))) || FAILED(device->CreateRenderTargetView(buffer.Get(), nullptr, &target))) return 21;
    ShowWindow(window, show);

    MSG message{};
    while (message.message != WM_QUIT) {
        if (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); continue; }
        const float time = GetTickCount64() / 1000.0f;
        const float color[] = {0.08f + 0.06f * std::sin(time), 0.18f, 0.42f + 0.12f * std::cos(time), 1.0f};
        context->OMSetRenderTargets(1, target.GetAddressOf(), nullptr);
        context->ClearRenderTargetView(target.Get(), color);
        if (FAILED(chain->Present(1, 0))) return 22;
    }
    return 0;
}
