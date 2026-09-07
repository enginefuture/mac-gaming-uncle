import AppKit
import Combine
import Carbon
import IndieCore
import IndieRuntime
@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
@preconcurrency import VideoToolbox

private final class InterpolationCaptureSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let continuation: AsyncStream<InterpolationImage>.Continuation
    private let lock = NSLock()
    private var count = 0
    // Never retain ScreenCaptureKit's limited IOSurfaces in the presentation
    // queue. Copy to our own bounded pool and release the capture buffer now.
    private var ownedPool: CVPixelBufferPool?
    private var transfer: VTPixelTransferSession?
    var capturedCount: Int { lock.withLock { count } }
    init(_ continuation: AsyncStream<InterpolationImage>.Continuation) { self.continuation = continuation }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let values = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = values.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let image = sample.imageBuffer else { return }
        lock.withLock { count += 1 }
        if ownedPool == nil {
            let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(image),
                kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(image),
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &ownedPool)
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
        }
        guard let ownedPool, let transfer else { return }
        var copy: CVPixelBuffer?
        let limit = [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, ownedPool, limit, &copy) == kCVReturnSuccess,
              let copy, VTPixelTransferSessionTransferImage(transfer, from: image, to: copy) == noErr else { return }
        continuation.yield(InterpolationImage(buffer: copy, timestamp: sample.presentationTimeStamp))
    }
    deinit { if let transfer { VTPixelTransferSessionInvalidate(transfer) } }
}

private func interpolationEmergencyStop(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    if #available(macOS 26, *) { Task { @MainActor in GameFrameInterpolation.shared.stop() } }
    return noErr
}

private final class PassthroughFrameWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 26, *)
@MainActor
final class GameFrameInterpolation: ObservableObject {
    /// Developer telemetry separates capture starvation from ML cost and presentation drops.
    /// None of these counters claims a physical display FPS measurement.
    struct DiagnosticSnapshot: Codable {
        let elapsedSeconds: Double
        let captured: Int
        let received: Int
        let generated: Int
        let submitted: Int
        let dropped: Int
        let backpressure: Int
        let active: Bool
    }
    var diagnostics: DiagnosticSnapshot {
        DiagnosticSnapshot(elapsedSeconds: Date().timeIntervalSince(began), captured: sink?.capturedCount ?? 0,
                           received: received, generated: processed, submitted: submitted,
                           dropped: dropped, backpressure: rendererBackpressure, active: active)
    }
    enum StopKind { case manual, transient, failure, replaced }
    var onStopped: ((StopKind) -> Void)?
    static let shared = GameFrameInterpolation()
    @Published private(set) var active = false
    @Published private(set) var status = L("插帧已关闭")
    @Published private(set) var metrics = ""
    @Published private(set) var windows: [SCWindow] = []
    private var stream: SCStream?
    private var sink: InterpolationCaptureSink?
    private var engine: FrameInterpolationEngine?
    private var worker: Task<Void, Never>?
    private var watchdog: Timer?
    private var overlay: NSWindow?
    private var layer: AVSampleBufferDisplayLayer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var generation = UUID()
    private var target: SCWindow?
    private var began = Date()
    private var lastProgress = Date()
    private var lastMetricUpdate = Date.distantPast
    private var hasOutput = false
    private var processed = 0
    private var submitted = 0
    private var dropped = 0
    private var received = 0
    private var rendererBackpressure = 0
    private var presentationOffset: Double?
    private var displayTopology = ""
    private var processingInFlight = false

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), interpolationEmergencyStop, 1, &eventType, nil, &handler)
        let keyID = EventHotKeyID(signature: 0x4D475546, id: 1)
        RegisterEventHotKey(UInt32(kVK_F12), UInt32(cmdKey | optionKey | controlKey), keyID,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    func refreshWindows() async {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            status = L("请在系统设置中允许屏幕录制，然后重新打开应用。无需麦克风权限。")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
                $0.windowLayer == 0 && $0.frame.width >= 320 && $0.frame.height >= 200 && !($0.title ?? "").isEmpty
            }.sorted { ($0.title ?? "") < ($1.title ?? "") }
        } catch { status = error.localizedDescription }
    }

    func start(windowID: CGWindowID, automatically: Bool = false, expectedPID: Int32? = nil) async {
        stop(kind: .replaced)
        guard hotKey != nil else { status = L("无法注册紧急停止快捷键，插帧未启动"); return }
        guard FrameInterpolationEngine.isSupported else { status = L("此设备不支持 VideoToolbox 插帧"); return }
        guard CGPreflightScreenCaptureAccess() else {
            if !automatically { await refreshWindows() }
            return
        }
        let token = generation
        active = true
        status = L("正在准备插帧；原游戏画面保持可见…")
        began = Date(); lastProgress = began
        displayTopology = topology()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLifetime() }
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard token == generation else { return }
            guard let window = content.windows.first(where: { $0.windowID == windowID }),
                  let owner = window.owningApplication,
                  owner.processID != ProcessInfo.processInfo.processIdentifier,
                  expectedPID == nil || expectedPID == owner.processID else {
                throw failure(L("游戏窗口已关闭，请重新选择"))
            }
            target = window
            if !automatically { NSRunningApplication(processIdentifier: owner.processID)?.activate(options: .activateAllWindows) }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let width = Int((filter.contentRect.width * Double(filter.pointPixelScale)).rounded())
            let height = Int((filter.contentRect.height * Double(filter.pointPixelScale)).rounded())
            guard width > 0, height > 0,
                  abs(Double(width) / Double(height) - window.frame.width / window.frame.height) < 0.01 else {
                throw failure(L("捕获尺寸与窗口比例不一致，已保留原画面"))
            }
            let processor = FrameInterpolationEngine(width: width, height: height)
            engine = processor
            try await processor.prepare()
            guard token == generation else { processor.close(); return }
            let config = SCStreamConfiguration()
            config.width = width; config.height = height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.capturesAudio = false; config.captureMicrophone = false
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 3
            let (frames, continuation) = AsyncStream<InterpolationImage>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let output = InterpolationCaptureSink(continuation)
            let capture = SCStream(filter: filter, configuration: config, delegate: nil)
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "indie.interpolation.capture"))
            stream = capture; sink = output
            try await capture.startCapture()
            guard token == generation else { try? await capture.stopCapture(); return }
            worker = Task { [weak self] in
                var previous: InterpolationImage?
                var previousSignature: FrameContentSignature?
                for await current in frames {
                    guard let self, token == self.generation, !Task.isCancelled else { return }
                    self.received += 1
                    let signature = self.signature(current.buffer)
                    defer { previous = current; previousSignature = signature }
                    guard let old = previous else { continue }
                    if self.identical(old.buffer, current.buffer) ||
                        (signature != nil && previousSignature != nil && signature!.isSceneCut(from: previousSignature!)) {
                        self.presentationOffset = nil
                        self.overlay?.orderOut(nil)
                        self.layer?.sampleBufferRenderer.flush()
                        // Scene cuts reveal the original immediately. Duplicate
                        // rejection uses exact pixels, never the sampled grid.
                        self.lastProgress = Date()
                        continue
                    }
                    let a = old.timestamp.seconds, b = current.timestamp.seconds
                    guard let midpoint = FrameInterpolationTiming.midpoint(previous: a, current: b) else {
                        self.presentationOffset = nil
                        self.overlay?.orderOut(nil)
                        continue
                    }
                    let began = Date()
                    self.processingInFlight = true
                    do {
                        let generated = try await processor.interpolate(previous: old, current: current)
                        guard token == self.generation else { return }
                        self.processingInFlight = false
                        let elapsed = Date().timeIntervalSince(began)
                        if elapsed > 0.1 { self.presentationOffset = nil; self.dropped += 2; continue }
                        self.processed += 1
                        self.present(generated: generated, current: current, midpoint: midpoint, gap: b-a, elapsed: elapsed)
                    } catch {
                        guard token == self.generation else { return }
                        self.processingInFlight = false
                        if (error as NSError).code == -12911 && !self.hasOutput && Date().timeIntervalSince(self.began) < 8 {
                            continue // Model loading; bounded by independent watchdog.
                        }
                        self.stop(reason: L("插帧失败，已恢复原画面：\(error.localizedDescription)"), kind: .failure)
                        return
                    }
                }
            }
        } catch {
            if token == generation { stop(reason: L("插帧未启动：\(error.localizedDescription)"), kind: .failure) }
        }
    }

    private func present(generated: InterpolationImage, current: InterpolationImage, midpoint: Double, gap: Double, elapsed: Double) {
        guard let target else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        if presentationOffset == nil { presentationOffset = now + gap / 2 - midpoint }
        let midPTS = midpoint + presentationOffset!
        guard !FrameInterpolationTiming.isLate(presentation: midPTS, now: now) else {
            dropped += 2; presentationOffset = nil; overlay?.orderOut(nil); return
        }
        if overlay == nil { createOverlay(frame: target.frame) }
        guard let layer, layer.sampleBufferRenderer.isReadyForMoreMediaData else {
            dropped += 2; rendererBackpressure += 1; return
        }
        for (image, pts) in [(generated, midPTS), (current, current.timestamp.seconds + presentationOffset!)] {
            var format: CMVideoFormatDescription?
            var sample: CMSampleBuffer?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image.buffer, formatDescriptionOut: &format) == noErr,
                  let format else { stop(reason: L("无法创建显示帧，已恢复原画面"), kind: .failure); return }
            var timing = CMSampleTimingInfo(duration: CMTime(seconds: gap/2, preferredTimescale: 60000),
                                            presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 60000), decodeTimeStamp: .invalid)
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image.buffer, formatDescription: format,
                                                           sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else {
                stop(reason: L("无法创建显示帧，已恢复原画面"), kind: .failure); return
            }
            layer.sampleBufferRenderer.enqueue(sample)
            submitted += 1
        }
        let runningStatus = L("2× 插帧运行中；切出游戏时暂停")
        if status != runningStatus { status = runningStatus }
        hasOutput = true
        lastProgress = Date()
        if overlay?.isVisible != true {
            let token = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + gap/2) { [weak self] in
                guard let self, self.active, self.generation == token else { return }
                self.overlay?.orderFrontRegardless()
            }
        }
        if Date().timeIntervalSince(lastMetricUpdate) > 0.5 {
            metrics = L("处理 \(CVPixelBufferGetWidth(current.buffer))×\(CVPixelBufferGetHeight(current.buffer)) · 耗时 \(Int(elapsed*1000)) ms · 生成 \(processed) 帧 · 提交 \(submitted) 帧 · 过期丢弃 \(dropped) 帧")
            lastMetricUpdate = Date()
        }
    }

    private func createOverlay(frame: CGRect) {
        let window = PassthroughFrameWindow(contentRect: appKitFrame(frame), styleMask: .borderless, backing: .buffered, defer: false)
        window.ignoresMouseEvents = true
        // An opaque window can cause the source application's occlusion
        // handling to stop producing frames as soon as our overlay appears.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let display = AVSampleBufferDisplayLayer()
        display.frame = view.bounds
        display.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1)
            display.controlTimebase = timebase
        }
        view.layer?.addSublayer(display)
        window.contentView = view
        overlay = window; layer = display
    }

    private func appKitFrame(_ cgFrame: CGRect) -> CGRect {
        CGRect(x: cgFrame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - cgFrame.maxY,
               width: cgFrame.width, height: cgFrame.height)
    }

    private func checkLifetime() {
        guard active else { return }
        if let pid = target?.owningApplication?.processID {
            guard NSRunningApplication(processIdentifier: pid) != nil else { stop(kind: .transient); return }
            if (hasOutput || Date().timeIntervalSince(began) > 3) && NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                stop(reason: L("已切出游戏，等待返回后恢复插帧"), kind: .transient); return
            }
        }
        guard displayTopology == topology() else {
            stop(reason: L("显示器或缩放变化，等待重新匹配窗口"), kind: .transient); return
        }
        if Date().timeIntervalSince(began) > 10 && !hasOutput {
            stop(reason: L("设备未及时生成插帧，已保留原画面（没有自动降低分辨率）"), kind: .failure); return
        }
        if hasOutput && Date().timeIntervalSince(lastProgress) > 0.5 {
            if processingInFlight {
                stop(reason: L("捕获或插帧停滞，已恢复原画面"), kind: .failure); return
            }
            overlay?.orderOut(nil)
            presentationOffset = nil
            status = L("画面暂无更新，显示原画面；更新后恢复插帧")
        }
        guard let target, let pid = target.owningApplication?.processID else { return }
        guard NSRunningApplication(processIdentifier: pid) != nil else { stop(kind: .transient); return }
        if Date().timeIntervalSince(began) > 3 && NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            stop(reason: L("已切出游戏，等待返回后恢复插帧"), kind: .transient); return
        }
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.windowID }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { stop(kind: .transient); return }
        if frame.size != target.frame.size || info[kCGWindowIsOnscreen as String] as? Bool != true {
            stop(reason: L("窗口尺寸或可见性变化，插帧停止"), kind: .transient); return
        }
        overlay?.setFrame(appKitFrame(frame), display: false)
        if layer?.sampleBufferRenderer.status == .failed { stop(reason: L("显示层异常，已恢复原画面"), kind: .failure) }
    }

    func stop(reason: String? = nil, kind: StopKind = .manual) {
        generation = UUID()
        active = false
        watchdog?.invalidate(); watchdog = nil
        worker?.cancel(); worker = nil
        sink?.continuation.finish(); sink = nil
        if let capture = stream { Task { try? await capture.stopCapture() } }
        stream = nil
        engine?.close(); engine = nil
        layer?.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil); layer = nil
        overlay?.orderOut(nil); overlay?.close(); overlay = nil
        target = nil; hasOutput = false; processed = 0; submitted = 0; dropped = 0; presentationOffset = nil
        received = 0; rendererBackpressure = 0
        processingInFlight = false
        status = reason ?? L("插帧已关闭")
        onStopped?(kind)
    }

    private func failure(_ description: String) -> NSError {
        NSError(domain: "Indie.FrameInterpolation", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func topology() -> String {
        NSScreen.screens.map {
            "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "?"):\($0.frame):\($0.backingScaleFactor)"
        }.joined(separator: ";")
    }

    private func signature(_ pixel: CVPixelBuffer) -> FrameContentSignature? {
        guard CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixel)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel), stride = CVPixelBufferGetBytesPerRow(pixel)
        guard width > 0, height > 0 else { return nil }
        var samples: [UInt8] = []
        for row in 0..<18 { for column in 0..<32 {
            let p = min(height-1, row*height/18)*stride + min(width-1, column*width/32)*4
            samples.append(UInt8((Int(base[p]) + 2*Int(base[p+1]) + Int(base[p+2]))/4))
        } }
        return FrameContentSignature(luma: samples)
    }

    private func identical(_ first: CVPixelBuffer, _ second: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(first), height = CVPixelBufferGetHeight(first)
        guard width == CVPixelBufferGetWidth(second), height == CVPixelBufferGetHeight(second),
              CVPixelBufferGetPixelFormatType(first) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetPixelFormatType(second) == kCVPixelFormatType_32BGRA else { return false }
        CVPixelBufferLockBaseAddress(first, .readOnly); CVPixelBufferLockBaseAddress(second, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(first, .readOnly); CVPixelBufferUnlockBaseAddress(second, .readOnly) }
        guard let a = CVPixelBufferGetBaseAddress(first), let b = CVPixelBufferGetBaseAddress(second) else { return false }
        for row in 0..<height {
            if memcmp(a.advanced(by: row*CVPixelBufferGetBytesPerRow(first)), b.advanced(by: row*CVPixelBufferGetBytesPerRow(second)), width*4) != 0 { return false }
        }
        return true
    }
}
