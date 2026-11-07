// sunboost: lift a MacBook XDR screen past SDR white so it stays readable in sunlight.
// The engine lives in Sources/Shared/Booster.swift and is shared with the app.
import AppKit

func selfTest() -> Never {
    func check(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) } }
    let t = Curve(gain: 4, shadows: 0.7, floor: 0.05).table(cap: 4)
    check(abs(t[255] - 4) < 1e-4, "white maps to the gain")
    check(abs(t[0] - 0.2) < 1e-4, "black maps to floor * gain")
    check(zip(t, t.dropFirst()).allSatisfy { $0 <= $1 }, "table never goes down")
    check(Curve(gain: 4, shadows: 1, floor: 0).table(cap: 2.5)[255] == 2.5, "gain is capped at headroom")
    var w = Watchdog()
    check(!w.tick(open: false) && !w.tick(open: false) && !w.tick(open: false), "watchdog waits")
    check(w.tick(open: false), "watchdog rebuilds after 4 closed ticks")
    check(!w.tick(open: true) && !w.tick(open: false), "an open tick resets the count")
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

guard let booster = Booster(curve: Curve(gain: gain, shadows: shadows, floor: floor)) else {
    print("No display with HDR headroom found. This needs a MacBook Pro or Air with an XDR or HDR screen.")
    exit(1)
}
func finish(_ why: String) -> Never {
    booster.stop()
    print(why)
    exit(0)
}
booster.onStopped = { why in print(why); exit(0) }

var keep: [Any] = []
for s in [SIGINT, SIGTERM, SIGHUP] {
    signal(s, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
    src.setEventHandler { finish("Stopped, screen back to normal.") }
    src.resume()
    keep.append(src)
}
NSApplication.shared.setActivationPolicy(.accessory)
booster.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    print(String(format: "Boosting at up to %.2fx (screen headroom %.2fx). Ctrl-C to stop.",
                 min(gain, booster.headroom), booster.headroom))
}
if seconds > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1 + seconds) { finish("Done, screen back to normal.") } }
NSApplication.shared.run()
