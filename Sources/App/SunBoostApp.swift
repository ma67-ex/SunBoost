import SwiftUI
import AppKit

private let amber = Color(red: 1.0, green: 0.70, blue: 0.24)
private let ember = Color(red: 1.0, green: 0.45, blue: 0.16)

// MARK: Model

final class Model: ObservableObject {
    /// Hard ceiling in the UI. The engine also caps at the live screen headroom.
    static let maxGain = 4.0

    @Published var on = false
    @Published var gain = 3.0 { didSet { push() } }
    @Published var shadows = 1.0 { didSet { push() } }
    @Published var floor = 0.0 { didSet { push() } }
    @Published var autoOff = 0
    @Published var headroom = 1.0
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var note = ""

    let booster: Booster?
    private var offTask: DispatchWorkItem?
    private var poll: Timer?

    init() {
        booster = Booster(curve: Curve(gain: 3, shadows: 1, floor: 0))
        booster?.onStopped = { [weak self] why in DispatchQueue.main.async { self?.on = false; self?.note = why } }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.booster?.stop()
        }
    }

    var available: Bool { booster != nil }
    /// What is really applied: the slider, capped by what the screen reports.
    var effectiveGain: Double { on && headroom > 1.05 ? min(gain, headroom) : 1.0 }

    func setOn(_ v: Bool) {
        guard let booster else { return }
        on = v
        offTask?.cancel()
        if v {
            note = ""
            booster.curve = curve
            booster.start()
            if autoOff > 0 {
                let task = DispatchWorkItem { [weak self] in self?.setOn(false); self?.note = "Auto-off timer finished." }
                offTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(autoOff) * 60, execute: task)
            }
        } else {
            booster.stop()
        }
    }

    var curve: Curve { Curve(gain: Float(gain), shadows: Float(shadows), floor: Float(floor)) }
    private func push() { booster?.curve = curve; booster?.apply() }
    private func refresh() {
        headroom = Double(booster?.headroom ?? 1)
        thermal = ProcessInfo.processInfo.thermalState
    }

    func preset(_ g: Double, _ s: Double, _ f: Double) { gain = g; shadows = s; floor = f }
}

// MARK: Views

/// Hover flag. A tiny ObservableObject because the SwiftUI macros plugin (@State) is not in the Command Line Tools.
final class Hover: ObservableObject { @Published var on = false }

struct PowerButton: View {
    @EnvironmentObject var m: Model
    @StateObject private var h = Hover()
    var body: some View {
        Button { m.setOn(!m.on) } label: {
            ZStack {
                Circle().fill(m.on
                    ? AnyShapeStyle(RadialGradient(colors: [amber, ember], center: .center, startRadius: 4, endRadius: 56))
                    : AnyShapeStyle(Color.white.opacity(h.on ? 0.10 : 0.07)))
                Circle().strokeBorder(Color.white.opacity(m.on ? 0.35 : 0.14), lineWidth: 1)
                Image(systemName: m.on ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(m.on ? Color.white : amber)
            }
            .frame(width: 96, height: 96)
            .shadow(color: m.on ? amber.opacity(0.65) : .clear, radius: 26)
            .scaleEffect(h.on ? 1.03 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: h.on)
            .animation(.easeOut(duration: 0.25), value: m.on)
        }
        .buttonStyle(.plain)
        .onHover { h.on = $0 }
        .disabled(!m.available)
        .accessibilityLabel(m.on ? "Turn boost off" : "Turn boost on")
    }
}

struct CurveView: View {
    var gain: Double, shadows: Double, floor: Double, cap: Double
    var body: some View {
        Canvas { ctx, size in
            let top = Model.maxGain
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: size.height - (y / top) * size.height) }
            var base = Path(); base.move(to: pt(0, 0)); base.addLine(to: pt(1, 1))
            ctx.stroke(base, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let m = min(gain, cap)
            var line = Path()
            for i in 0...64 {
                let x = Double(i) / 64
                let y = floor * m + (1 - floor) * m * pow(x, shadows)
                i == 0 ? line.move(to: pt(x, y)) : line.addLine(to: pt(x, y))
            }
            var fill = line; fill.addLine(to: pt(1, 0)); fill.addLine(to: pt(0, 0)); fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [amber.opacity(0.35), amber.opacity(0.02)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(amber), lineWidth: 2)
        }
        .frame(height: 74)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .overlay(alignment: .topLeading) {
            Text("Dashed line = normal screen").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).padding(6)
        }
        .accessibilityHidden(true)
    }
}

struct Row: View {
    var title: String, value: String
    @Binding var v: Double
    var range: ClosedRange<Double>
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
            Slider(value: $v, in: range).tint(amber)
        }
    }
}

struct Chip: View {
    var label: String, action: () -> Void
    @StateObject private var h = Hover()
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(h.on ? 0.14 : 0.08)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain).onHover { h.on = $0 }
    }
}

struct MainView: View {
    @EnvironmentObject var m: Model

    var thermalText: (String, Color) {
        switch m.thermal {
        case .nominal: return ("Cool", .green)
        case .fair: return ("Warm", .yellow)
        case .serious: return ("Hot", .orange)
        default: return ("Critical", .red)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("SunBoost").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                Text(!m.available ? "No HDR screen found"
                     : m.on ? (m.headroom > 1.05 ? String(format: "%.1f× brighter than normal", m.effectiveGain) : "Opening headroom…")
                     : "Off")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.numericText())
            }
            PowerButton().padding(.vertical, 2)

            VStack(spacing: 14) {
                Row(title: "Brightness boost", value: String(format: "%.1f×", m.gain), v: $m.gain, range: 1...Model.maxGain)
                HStack(spacing: 8) {
                    Chip(label: "Comfort") { m.preset(2.5, 1, 0) }
                    Chip(label: "Sun") { m.preset(4, 1, 0) }
                    Chip(label: "Glare") { m.preset(4, 0.7, 0.05) }
                }
                Row(title: "Lift dark areas", value: String(format: "%.0f%%", (1 - m.shadows) * 200), v: Binding(get: { 1 - m.shadows }, set: { m.shadows = 1 - $0 }), range: 0...0.5)
                Row(title: "Lift black", value: String(format: "%.0f%%", m.floor * 100 / 0.3), v: $m.floor, range: 0...0.3)
                CurveView(gain: m.gain, shadows: m.shadows, floor: m.floor, cap: m.on && m.headroom > 1.05 ? m.headroom : Model.maxGain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .opacity(m.available ? 1 : 0.4).disabled(!m.available)

            HStack {
                Text("Auto-off").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Picker("", selection: $m.autoOff) {
                    Text("Never").tag(0); Text("10 min").tag(10); Text("30 min").tag(30); Text("1 hour").tag(60)
                }
                .labelsHidden().frame(width: 100)
            }

            HStack(spacing: 8) {
                Circle().fill(thermalText.1).frame(width: 8, height: 8)
                Text("Mac is \(thermalText.0.lowercased())").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text(String(format: "Screen allows %.1f×", m.headroom)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
            }

            if !m.note.isEmpty {
                Text(m.note).font(.system(size: 12)).foregroundStyle(amber).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("4.0× is the limit macOS reports for this screen, so it is the safe maximum. High brightness heats the Mac and drains the battery. Turn it off when you go indoors.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 360)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.09, blue: 0.07), Color(red: 0.06, green: 0.05, blue: 0.05)], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }
}

struct MenuContent: View {
    @EnvironmentObject var m: Model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Toggle("Boost", isOn: Binding(get: { m.on }, set: { m.setOn($0) })).disabled(!m.available)
        Divider()
        Button("Open SunBoost") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit") { m.booster?.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@main
struct SunBoostApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        Window("SunBoost", id: "main") { MainView().environmentObject(model) }
            .windowResizability(.contentSize)
        MenuBarExtra("SunBoost", systemImage: model.on ? "sun.max.fill" : "sun.max") {
            MenuContent().environmentObject(model)
        }
    }
}
