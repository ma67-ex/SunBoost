// sunboost: lift a MacBook XDR screen past SDR white so it stays readable in sunlight.
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

func selfTest() -> Never {
    func check(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) } }
    let t = Curve(gain: 4, shadows: 0.7, floor: 0.05).table(cap: 4)
    check(abs(t[255] - 4) < 1e-4, "white maps to the gain")
    check(abs(t[0] - 0.2) < 1e-4, "black maps to floor * gain")
    check(zip(t, t.dropFirst()).allSatisfy { $0 <= $1 }, "table never goes down")
    check(Curve(gain: 4, shadows: 1, floor: 0).table(cap: 2.5)[255] == 2.5, "gain is capped at headroom")
    print("ok")
    exit(0)
}

let usage = """
usage: sunboost [--gain 4.0] [--shadows 1.0] [--floor 0.0] [--seconds N]

  --gain     brightness multiplier, 1 to 8. Capped at the screen's live headroom (about 4 on XDR).
  --shadows  below 1 lifts dark tones, 0.5 to 1.5. Default 1 (straight scale).
  --floor    lifts pure black, 0 to 0.3. Default 0.
  --seconds  stop after N seconds. Default: run until Ctrl-C.
  --selftest check the curve maths and exit.

Stop with Ctrl-C. The screen goes back to normal right away.
"""

var gain: Float = 4.0, shadows: Float = 1.0, floor: Float = 0.0, seconds = 0.0
var it = CommandLine.arguments.dropFirst().makeIterator()
func number(_ name: String) -> Double {
    guard let s = it.next(), let v = Double(s) else { print("\(name) needs a number\n\n\(usage)"); exit(2) }
    return v
}
while let a = it.next() {
    switch a {
    case "--gain": gain = Float(min(max(number(a), 1), 8))
    case "--shadows": shadows = Float(min(max(number(a), 0.5), 1.5))
    case "--floor": floor = Float(min(max(number(a), 0), 0.3))
    case "--seconds": seconds = max(number(a), 0)
    case "--selftest": selfTest()
    case "-h", "--help": print(usage); exit(0)
    default: print("unknown option \(a)\n\n\(usage)"); exit(2)
    }
}

func displayID(of s: NSScreen) -> CGDirectDisplayID {
    s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
}
let hdrScreens = NSScreen.screens.filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
guard let screen = hdrScreens.first(where: { CGDisplayIsBuiltin(displayID(of: $0)) != 0 }) ?? hdrScreens.first else {
    print("No display with HDR headroom found. This needs a MacBook Pro or Air with an XDR or HDR screen.")
    exit(1)
}
let id = displayID(of: screen)
let curve = Curve(gain: gain, shadows: shadows, floor: floor)

// Draws one empty frame at 30 fps. Without a draw call macOS never enters HDR mode.
final class Drawer: NSObject, MTKViewDelegate {
    let queue = MTLCreateSystemDefaultDevice()!.makeCommandQueue()!
    func mtkView(_ v: MTKView, drawableSizeWillChange s: CGSize) {}
    func draw(in v: MTKView) {
        guard let d = v.currentDrawable, let p = v.currentRenderPassDescriptor,
              let c = queue.makeCommandBuffer(), let e = c.makeRenderCommandEncoder(descriptor: p) else { return }
        e.endEncoding(); c.present(d); c.commit()
    }
}
let drawer = Drawer()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: NSRect(origin: screen.frame.origin, size: NSSize(width: 1, height: 1)),
                   styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver
win.ignoresMouseEvents = true
win.isOpaque = false
win.backgroundColor = .clear
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

func stop(_ why: String) -> Never {
    CGDisplayRestoreColorSyncSettings()
    print(why)
    exit(0)
}

// Re-applied every 2 s: follows live headroom, survives sleep, wake and display changes.
// If headroom reads 1.0 the cap makes the table a no-op, so a failed overlay is harmless.
func apply() {
    let state = ProcessInfo.processInfo.thermalState
    if state == .serious || state == .critical { stop("Mac is running hot, boost turned off.") }
    let t = curve.table(cap: Float(screen.maximumExtendedDynamicRangeColorComponentValue))
    CGSetDisplayTransferByTable(id, 256, t, t, t)
}

var keep: [Any] = []
for s in [SIGINT, SIGTERM, SIGHUP] {
    signal(s, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
    src.setEventHandler { stop("Stopped, screen back to normal.") }
    src.resume()
    keep.append(src)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    apply()
    print(String(format: "Boosting at up to %.2fx (screen headroom %.2fx). Ctrl-C to stop.",
                 min(gain, Float(screen.maximumExtendedDynamicRangeColorComponentValue)),
                 screen.maximumExtendedDynamicRangeColorComponentValue))
    keep.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in apply() })
}
if seconds > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1 + seconds) { stop("Done, screen back to normal.") } }
app.run()
