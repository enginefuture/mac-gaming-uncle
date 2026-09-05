#include <windows.h>
#include <xinput.h>
#include <cstdio>

int wmain() {
    bool connected = false;
    for (DWORD index = 0; index < XUSER_MAX_COUNT; ++index) {
        XINPUT_STATE state{};
        const DWORD result = XInputGetState(index, &state);
        if (result == ERROR_SUCCESS) {
            connected = true;
            ::wprintf(
                L"controller=%lu packet=%lu buttons=0x%04x left=(%d,%d) right=(%d,%d) triggers=(%u,%u)\n",
                index, state.dwPacketNumber, state.Gamepad.wButtons,
                state.Gamepad.sThumbLX, state.Gamepad.sThumbLY,
                state.Gamepad.sThumbRX, state.Gamepad.sThumbRY,
                state.Gamepad.bLeftTrigger, state.Gamepad.bRightTrigger
            );
        } else {
            ::wprintf(L"controller=%lu unavailable error=%lu\n", index, result);
        }
    }
    return connected ? 0 : 2;
}
