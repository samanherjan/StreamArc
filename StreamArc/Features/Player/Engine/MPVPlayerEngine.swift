// MPVPlayerEngine.swift
//
// Wraps libmpv (via MPVKit) as a PlayerEngine backend.
//
// ⚠️  IMPORTANT – FFmpeg conflict
// Both KSPlayer (via kingslay/FFmpegKit) and MPVKit bundle their own
// copies of FFmpeg. Linking both into the same target produces duplicate-
// symbol linker errors. To enable MPV you must do ONE of the following:
//
//   A) Remove KSPlayer from the target and use MPV as the primary engine.
//   B) Add MPVKit to project.yml, resolve the duplicate-FFmpeg conflict via
//      a custom "FFmpeg-shared" local package, and add  -DMPVKIT_ENABLED
//      to OTHER_SWIFT_FLAGS for the target.
//
// Until one of those steps is taken the file compiles as a stub that
// returns an error view. No build errors will occur.
// ─────────────────────────────────────────────────────────────────────────

#if !os(tvOS)
import SwiftUI
import Foundation
#if canImport(Libmpv)
import Libmpv
import MetalKit
#endif

// MARK: - MPVPlayerEngine

@MainActor
final class MPVPlayerEngine: PlayerEngine {

    let engineType: PlayerEngineType = .mpv

    private(set) var engineState: PlayerEngineState = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    var onStateChanged: (@MainActor (PlayerEngineState) -> Void)?
    var onTimeUpdate: (@MainActor (Double, Double) -> Void)?

#if canImport(Libmpv)
    // ── Real implementation when Libmpv is available in the build graph ──

    private var mpv: OpaquePointer?
    private let mpvQueue = DispatchQueue(label: "com.streamarc.mpvengine", qos: .userInitiated)
    private var timeTask: Task<Void, Never>?
    private weak var metalLayerRef: CAMetalLayer?

    func load(url: URL, options: PlayerEngineOptions) {
        teardown()
        setupMPV(url: url, options: options)
        startTimePolling()
        transition(to: .loading)
    }

    func play() {
        setFlag("pause", false)
        if engineState == .paused { transition(to: .playing) }
    }

    func pause() {
        setFlag("pause", true)
        if engineState == .playing || engineState == .buffering {
            transition(to: .paused)
        }
    }

    func seek(to seconds: Double) {
        command("seek", args: [String(seconds), "absolute"])
    }

    func teardown() {
        timeTask?.cancel()
        timeTask = nil
        if let ctx = mpv {
            command("stop")
            mpvQueue.async {
                mpv_terminate_destroy(ctx)
            }
            mpv = nil
        }
        transition(to: .idle)
    }

    func makePlayerView() -> AnyView {
        AnyView(MPVMetalViewRepresentable(engine: self))
    }

    // MARK: Internals

    fileprivate func attachMetalLayer(_ layer: CAMetalLayer) {
        metalLayerRef = layer
        guard let ctx = mpv else { return }
        var layerPtr: UnsafeMutableRawPointer? =
            Unmanaged.passUnretained(layer).toOpaque()
        mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &layerPtr)
    }

    private func setupMPV(url: URL, options: PlayerEngineOptions) {
        let ctx = mpv_create()
        guard let ctx else { return }
        mpv = ctx

        mpv_request_log_messages(ctx, "warn")
        mpv_set_option_string(ctx, "vo", "gpu-next")
        mpv_set_option_string(ctx, "gpu-api", "vulkan")
        mpv_set_option_string(ctx, "gpu-context", "moltenvk")
        mpv_set_option_string(ctx, "hwdec", "videotoolbox")
        mpv_set_option_string(ctx, "video-rotate", "no")

        if let ua = options.userAgent {
            mpv_set_option_string(ctx, "user-agent", ua)
        }
        if !options.headers.isEmpty {
            let headerString = options.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            mpv_set_option_string(ctx, "http-header-fields", headerString)
        }
        if options.isLiveTV {
            mpv_set_option_string(ctx, "cache", "no")
            mpv_set_option_string(ctx, "demuxer-cache-wait", "no")
        }

        mpv_set_wakeup_callback(ctx, { ctx in
            guard let ctx else { return }
            let engine = Unmanaged<MPVPlayerEngine>.fromOpaque(ctx).takeUnretainedValue()
            engine.mpvQueue.async { engine.readEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())

        mpv_observe_property(ctx, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, 0, "core-idle", MPV_FORMAT_FLAG)

        mpv_initialize(ctx)
        command("loadfile", args: [url.absoluteString])
    }

    private func readEvents() {
        guard let ctx = mpv else { return }
        while true {
            let event = mpv_wait_event(ctx, 0)
            guard let event else { break }
            if event.pointee.event_id == MPV_EVENT_NONE { break }
            switch event.pointee.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                if let prop = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data)) {
                    handlePropertyChange(prop.pointee)
                }
            case MPV_EVENT_PLAYBACK_RESTART:
                Task { @MainActor [weak self] in self?.transition(to: .playing) }
            case MPV_EVENT_END_FILE:
                Task { @MainActor [weak self] in self?.transition(to: .idle) }
            case MPV_EVENT_SHUTDOWN:
                return
            default: break
            }
        }
    }

    private func handlePropertyChange(_ prop: mpv_event_property) {
        let name = String(cString: prop.name)
        switch name {
        case "paused-for-cache":
            if let v = UnsafePointer<Bool>(OpaquePointer(prop.data))?.pointee, v {
                Task { @MainActor [weak self] in self?.transition(to: .buffering) }
            }
        case "pause":
            if let v = UnsafePointer<Bool>(OpaquePointer(prop.data))?.pointee {
                Task { @MainActor [weak self] in
                    self?.transition(to: v ? .paused : .playing)
                }
            }
        default: break
        }
    }

    private func startTimePolling() {
        timeTask?.cancel()
        timeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let ctx = self.mpv, !Task.isCancelled else { break }
                var ct = Double(0)
                var dt = Double(0)
                mpv_get_property(ctx, "time-pos",  MPV_FORMAT_DOUBLE, &ct)
                mpv_get_property(ctx, "duration",  MPV_FORMAT_DOUBLE, &dt)
                self.currentTime = ct
                self.duration    = dt
                self.onTimeUpdate?(ct, dt)
            }
        }
    }

    @discardableResult
    private func command(_ cmd: String, args: [String?] = []) -> Int32 {
        guard let ctx = mpv else { return -1 }
        var cargs: [UnsafePointer<CChar>?] = ([cmd] + args + [nil]).map {
            $0.flatMap { strdup($0) }.map { UnsafePointer($0) }
        }
        defer { cargs.forEach { if let p = $0 { free(UnsafeMutablePointer(mutating: p)) } } }
        return mpv_command(ctx, &cargs)
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let ctx = mpv else { return }
        var v: Int = value ? 1 : 0
        mpv_set_property(ctx, name, MPV_FORMAT_FLAG, &v)
    }

    private func transition(to new: PlayerEngineState) {
        guard engineState != new else { return }
        engineState = new
        onStateChanged?(new)
    }

#else
    // ── Stub when Libmpv is not linked ────────────────────────────────────
    // This compiles cleanly and shows an informative placeholder view.

    func load(url: URL, options: PlayerEngineOptions) {
        transition(to: .error("MPV is not enabled. See MPVPlayerEngine.swift for setup instructions."))
    }
    func play()   {}
    func pause()  {}
    func seek(to seconds: Double) {}
    func teardown() { transition(to: .idle) }

    func makePlayerView() -> AnyView {
        AnyView(
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("MPV not enabled")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Add MPVKit and resolve the FFmpeg conflict.\nSee MPVPlayerEngine.swift for instructions.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        )
    }

    private func transition(to new: PlayerEngineState) {
        guard engineState != new else { return }
        engineState = new
        onStateChanged?(new)
    }
#endif
}

// MARK: - Metal View (only compiled when Libmpv is available)

#if canImport(Libmpv)
private struct MPVMetalViewRepresentable: UIViewRepresentable {
    let engine: MPVPlayerEngine

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let metalLayer = CAMetalLayer()
        metalLayer.frame = container.bounds
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        container.layer.addSublayer(metalLayer)
        engine.attachMetalLayer(metalLayer)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.compactMap({ $0 as? CAMetalLayer }).first {
            layer.frame = uiView.bounds
        }
    }
}
#endif

#endif // !os(tvOS)
