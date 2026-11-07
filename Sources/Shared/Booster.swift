// Shared engine for the command line tool and the app.
//
// 1. A 1x1 px extended-dynamic-range Metal layer keeps macOS in HDR mode, which opens
//    brightness headroom the panel normally keeps for HDR video.
// 2. The display transfer table is scaled past 1.0, so everything on screen gets brighter.
//
// Public APIs only. The transfer table belongs to this process: if it exits, macOS restores it.
import AppKit
import MetalKit

struct Curve {
    var gain: Float, shadows: Float, floor: Float

    /// 256-entry ramp. 0 maps to floor * m, 255 maps to m, where m = min(gain, cap).
    /// shadows < 1 lifts dark tones; floor lifts true black so glare does not swallow it.
    func table(cap: Float) -> [Float] {
        let m = min(gain, cap)
        return (0..<256).map { i in
            floor * m + (1 - floor) * m * powf(Float(i) / 255, shadows)
        }
    }
}

/// Counts ticks where the screen headroom is still closed. After `limit` in a row the overlay is rebuilt.
struct Watchdog {
    static let limit = 4
    private(set) var closed = 0
    /// Returns true when the overlay should be rebuilt.
    mutating func tick(open: Bool) -> Bool {
        if open { closed = 0; return false }
        closed += 1
        if closed >= Watchdog.limit { closed = 0; return true }
        return false
    }
}

/// Draws one empty frame at 30 fps. Without a draw call macOS never enters HDR mode.
final class Drawer: NSObject, MTKViewDelegate {
    let queue = MTLCreateSystemDefaultDevice()!.makeCommandQueue()!
    func mtkView(_ v: MTKView, drawableSizeWillChange s: CGSize) {}
    func draw(in v: MTKView) {
        guard let d = v.currentDrawable, let p = v.currentRenderPassDescriptor,
              let c = queue.makeCommandBuffer(), let e = c.makeRenderCommandEncoder(descriptor: p) else { return }
        e.endEncoding(); c.present(d); c.commit()
    }
}

final class Booster {
    let screen: NSScreen
    let id: CGDirectDisplayID
    var curve: Curve
    /// Called after the booster stopped itself, e.g. because the Mac got hot.
    var onStopped: ((String) -> Void)?
    private var window: NSWindow?
    private var timer: Timer?
    private var watchdog = Watchdog()
    private var activity: NSObjectProtocol?
    private let drawer = Drawer()

    var isRunning: Bool { window != nil }
    var headroom: Float { Float(screen.maximumExtendedDynamicRangeColorComponentValue) }

    static func displayID(of s: NSScreen) -> CGDirectDisplayID {
        s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    }

    /// Built-in screen first, any other HDR screen otherwise. nil when nothing has HDR headroom.
    static var hdrScreen: NSScreen? {
        let all = NSScreen.screens.filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
        return all.first { CGDisplayIsBuiltin(displayID(of: $0)) != 0 } ?? all.first
    }

    init?(curve: Curve) {
        guard let s = Booster.hdrScreen else { return nil }
        screen = s
        id = Booster.displayID(of: s)
        self.curve = curve
    }

    func start() {
        guard window == nil else { return }
        _ = NSApplication.shared
        // Without this, App Nap can throttle the hidden overlay and macOS closes the headroom again.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "SunBoost keeps HDR headroom open")
        makeWindow()
        // Headroom opens about a second after the first frame. Re-applied every 2 s after that:
        // follows live headroom, survives sleep, wake and display changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.apply() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.apply() }
    }

    private func makeWindow() {
        let win = NSWindow(contentRect: NSRect(origin: screen.frame.origin, size: NSSize(width: 1, height: 1)),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: MTLCreateSystemDefaultDevice())
        let layer = view.layer as! CAMetalLayer
        layer.wantsExtendedDynamicRangeContent = true
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.colorPixelFormat = .rgba16Float
        view.clearColor = MTLClearColor(red: 1.5, green: 1.5, blue: 1.5, alpha: 1)
        view.delegate = drawer
        view.preferredFramesPerSecond = 30
        win.contentView = view
        win.orderFrontRegardless()
        window = win
    }

    func stop() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        watchdog = Watchdog()
        CGDisplayRestoreColorSyncSettings()
    }

    /// If headroom is still closed (about 1.0) the table is left alone, so a failed overlay is harmless.
    func apply() {
        guard isRunning else { return }
        let state = ProcessInfo.processInfo.thermalState
        if state == .serious || state == .critical {
            stop(); onStopped?("Mac is running hot, boost turned off.")
            return
        }
        let open = headroom > 1.05
        if watchdog.tick(open: open) { window?.orderOut(nil); window = nil; makeWindow() }
        guard open else { CGDisplayRestoreColorSyncSettings(); return }
        let t = curve.table(cap: headroom)
        CGSetDisplayTransferByTable(id, 256, t, t, t)
    }
}
