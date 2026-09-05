import Foundation
import IndieCore

public enum ControllerLaunchEnvironment {
    /// Wine supports XInput/DInput itself. Enhanced mode enables SDL's HIDAPI
    /// paths used by many games for PlayStation, Switch and generic USB/Bluetooth
    /// controllers, while retaining the conventional Xbox button positions.
    public static func make(mode: ControllerMode, rumble: Bool) -> [String: String] {
        let rumbleValue = rumble ? "1" : "0"
        var environment = [
            "SDL_JOYSTICK_HIDAPI": "1",
            "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1",
            "SDL_GAMECONTROLLER_USE_BUTTON_LABELS": "0",
        ]
        guard mode == .enhanced else { return environment }
        environment.merge([
            "SDL_JOYSTICK_HIDAPI_PS4": "1",
            "SDL_JOYSTICK_HIDAPI_PS4_RUMBLE": rumbleValue,
            "SDL_JOYSTICK_HIDAPI_PS5": "1",
            "SDL_JOYSTICK_HIDAPI_PS5_RUMBLE": rumbleValue,
            "SDL_JOYSTICK_HIDAPI_SWITCH": "1",
        ]) { _, configured in configured }
        return environment
    }
}
