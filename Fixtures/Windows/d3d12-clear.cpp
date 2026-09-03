#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <cmath>

using Microsoft::WRL::ComPtr;
static constexpr UINT FrameCount = 2;

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_KEYDOWN && wparam == VK_ESCAPE) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    WNDCLASSW klass{}; klass.lpfnWndProc = WindowProc; klass.hInstance = instance;
    klass.lpszClassName = L"IndieD3D12Fixture"; klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&klass)) return 10;
    HWND window = CreateWindowExW(0, klass.lpszClassName, L"Indie Compatibility Lab — Direct3D 12", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 1280, 720, nullptr, nullptr, instance, nullptr);
    if (!window) return 11;

    ComPtr<IDXGIFactory4> factory;
    ComPtr<ID3D12Device> device;
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 20;
    if (FAILED(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)))) {
        MessageBoxW(window, L"D3D12CreateDevice failed", L"Indie", MB_ICONERROR); return 21;
    }

    D3D12_COMMAND_QUEUE_DESC queueDescription{};
    queueDescription.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue;
    if (FAILED(device->CreateCommandQueue(&queueDescription, IID_PPV_ARGS(&queue)))) return 22;

    DXGI_SWAP_CHAIN_DESC1 swapDescription{};
    swapDescription.BufferCount = FrameCount; swapDescription.Width = 1280; swapDescription.Height = 720;
    swapDescription.Format = DXGI_FORMAT_R8G8B8A8_UNORM; swapDescription.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapDescription.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD; swapDescription.SampleDesc.Count = 1;
    ComPtr<IDXGISwapChain1> temporarySwap;
    if (FAILED(factory->CreateSwapChainForHwnd(queue.Get(), window, &swapDescription, nullptr, nullptr, &temporarySwap))) return 23;
    ComPtr<IDXGISwapChain3> swapChain;
    if (FAILED(temporarySwap.As(&swapChain))) return 24;

    D3D12_DESCRIPTOR_HEAP_DESC heapDescription{};
    heapDescription.NumDescriptors = FrameCount; heapDescription.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    ComPtr<ID3D12DescriptorHeap> rtvHeap;
    if (FAILED(device->CreateDescriptorHeap(&heapDescription, IID_PPV_ARGS(&rtvHeap)))) return 25;
    const UINT descriptorSize = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE handle = rtvHeap->GetCPUDescriptorHandleForHeapStart();
    ComPtr<ID3D12Resource> renderTargets[FrameCount];
    ComPtr<ID3D12CommandAllocator> allocators[FrameCount];
    for (UINT index = 0; index < FrameCount; ++index) {
        if (FAILED(swapChain->GetBuffer(index, IID_PPV_ARGS(&renderTargets[index])))) return 26;
        device->CreateRenderTargetView(renderTargets[index].Get(), nullptr, handle);
        handle.ptr += descriptorSize;
        if (FAILED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocators[index])))) return 27;
    }

    ComPtr<ID3D12GraphicsCommandList> list;
    if (FAILED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocators[0].Get(), nullptr, IID_PPV_ARGS(&list)))) return 28;
    list->Close();
    ComPtr<ID3D12Fence> fence;
    if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)))) return 29;
    HANDLE fenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!fenceEvent) return 30;
    UINT64 fenceValue = 0;
    ShowWindow(window, show);

    MSG message{};
    while (message.message != WM_QUIT) {
        if (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); continue; }
        const UINT frame = swapChain->GetCurrentBackBufferIndex();
        allocators[frame]->Reset();
        list->Reset(allocators[frame].Get(), nullptr);

        D3D12_RESOURCE_BARRIER toRender{};
        toRender.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        toRender.Transition.pResource = renderTargets[frame].Get();
        toRender.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        toRender.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        toRender.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        list->ResourceBarrier(1, &toRender);
        D3D12_CPU_DESCRIPTOR_HANDLE current = rtvHeap->GetCPUDescriptorHandleForHeapStart();
        current.ptr += static_cast<SIZE_T>(frame) * descriptorSize;
        const float time = GetTickCount64() / 1000.0f;
        const float color[] = {0.30f + 0.12f * std::sin(time), 0.06f, 0.34f + 0.12f * std::cos(time), 1.0f};
        list->OMSetRenderTargets(1, &current, FALSE, nullptr);
        list->ClearRenderTargetView(current, color, 0, nullptr);
        D3D12_RESOURCE_BARRIER toPresent = toRender;
        toPresent.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        toPresent.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &toPresent);
        list->Close();
        ID3D12CommandList* lists[] = {list.Get()};
        queue->ExecuteCommandLists(1, lists);
        if (FAILED(swapChain->Present(1, 0))) { CloseHandle(fenceEvent); return 31; }
        ++fenceValue; queue->Signal(fence.Get(), fenceValue);
        if (fence->GetCompletedValue() < fenceValue) {
            fence->SetEventOnCompletion(fenceValue, fenceEvent);
            WaitForSingleObject(fenceEvent, INFINITE);
        }
    }
    ++fenceValue; queue->Signal(fence.Get(), fenceValue);
    if (fence->GetCompletedValue() < fenceValue) {
        fence->SetEventOnCompletion(fenceValue, fenceEvent); WaitForSingleObject(fenceEvent, INFINITE);
    }
    CloseHandle(fenceEvent);
    return 0;
}
