# Universal frame interpolation — experimental, opt-in

Included in the 0.4.0 research preview. The application exposes 2× only, off by
default. Internal 4×/static-detail laboratory APIs are not enabled by the UI.

## Scope

- macOS 26+, Apple Silicon, one active game window, SDR, 2× only.
- Per-game opt-in persisted in GameConfiguration; missing legacy value means off.
- Game Settings → Universal Frame Interpolation → Open panel. Enable automatic
  following once. Authorize screen capture explicitly if necessary, then start the
  game normally. Full executable path + PID + process start time identify a run;
  title text is not used to identify the game. Multiple matching processes are
  considered ambiguous and do not trigger capture.
- The foreground game's largest eligible window must have stable dimensions in two
  consecutive one-second observations. Capture still waits for valid moving frames.
  Switching away tears down the stream/overlay; returning rechecks and restarts.
  A rebuilt window or changed dimensions are matched again. Static frames reveal the
  original without forcing a restart. Unsupported windows fail once, not every poll.
- Manual Stop or the emergency key suppresses automatic restart for currently
  observed game runs, including focus changes and window rebuilds. A new PID/start-time
  identity resets suppression. The panel's Rearm button explicitly clears suppression.
- Closing the interpolation panel does not stop automatic following. Disabling its
  saved preference removes that game's watcher. Application quit cancels all watchers.
- First screen-capture authorization is user-controlled; no microphone permission,
  audio capture, recording to disk, DLL injection, Wine/DPI change or input remapping.
- Control + Option + Command + F12 is a globally registered emergency stop. Switching
  away, target closure/minimization/resizing, display changes or
  watchdog expiry removes the overlay. The original game remains untouched.
- Exclusive fullscreen is outside the supported first-version scope.

## Pipeline

SCStream (target window only, no cursor/audio) → bounded owned IOSurface pool →
single-slot newest-frame stream → exact duplicate and sampled scene-cut checks →
VideoToolbox frame processor → timed original/interpolated pair → nonactivating,
mouse-through AVSampleBufferDisplayLayer overlay at the original window bounds.

Model preparation and conversion/inference run on a private queue. Only one request
can be in flight. The independent UI watchdog can remove the overlay even if the
processor stalls. No silent downscaling. Backend errors retain the original image.

Capture buffers MUST NOT be retained by the display queue: doing so exhausted the
ScreenCaptureKit surface pool in the initial prototype. The corrected implementation
transfers to a private pool limited to 8 buffers before releasing the capture frame.
The stream queue remains depth 3 with bufferingNewest(1).

Frame submission counts are not measured monitor FPS or engine simulation FPS.
Capture lacks engine motion/depth/UI buffers; HUD artifacts and added latency remain
possible. Scene-cut detection is heuristic; duplicate rejection compares full pixels.

## Local evidence: M3 Max / macOS 26.6.2, 2026-09-07

- Synthetic processor probe: 1280×720 produced six intermediate frames, roughly
  9–14 ms per request after initialization.
- 1920×1080 generation failed with VTFrameProcessorErrorDomain -19730,
  "Processor is not initialized". A non-nil configuration and isSupported=true do
  NOT establish resolution support. No claim of working 1080p on this machine.
- End-to-end moving-window capture: after buffer-ownership fix, a 12-second test
  stayed active, generated 359 frames and submitted 716 original/intermediate
  frames, with 2 expired frames. These are submission counts, not measured display FPS.
- Mouse-through test incremented the underlying window's click counter.
- System Events hotkey test stopped interpolation while the target remained active.
- Initial stalls triggered fallback safely. No game settings were modified by tests.

Fixtures: FrameInterpolationProbe.swift, InterpolationPattern.swift,
InterpolationCaptureProbe.swift. Unit tests cover admission timing, invalid/repeated
timestamps, scene cuts, legacy/default-off preference persistence, automatic following
state transitions, run-scoped manual suppression and process identity parsing.

## Remaining acceptance

Real game quality/latency, sustained operation, multi-display movement and an actual
displayed-FPS measurement require further testing. Start with a manually configured
1280×720 window; never force existing games to that size from this module. First
rollout stays experimental, opt-in, and is not a promise to support every game.

References / prior art:

- https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration
- https://developer.apple.com/videos/play/wwdc2022/10155/ — IOSurface pool lifetime
- https://github.com/Lospi/MetalDuck — public architecture reference, not bundled
