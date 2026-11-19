import AppKit
import ServiceManagement
import UserNotifications

enum Scale {
    static let deadZone: CGFloat = 30
    static let step: CGFloat = 28
    static let marks: [Double] = [30, 60, 120, 180, 300, 420, 600, 900, 1200, 1800, 2700, 3600,
                                  5400, 7200, 10800, 14400, 21600, 28800, 43200, 86400]

    static func seconds(forDistance d: CGFloat, _ marks: [Double] = marks) -> Double? {
        guard d >= deadZone else { return nil }
        return marks[min(Int((d - deadZone) / step), marks.count - 1)]
    }

    static func distance(forSeconds s: Double, _ marks: [Double] = marks) -> CGFloat {
        deadZone + step * CGFloat(marks.firstIndex(of: s) ?? 0)
    }
}

func spoken(_ s: Double) -> String {
    let t = Int(s.rounded())
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
    if m > 0 { return sec > 0 ? "\(m) min \(sec) s" : "\(m) min" }
    return "\(sec) s"
}

func short(_ s: Double) -> String {
    let t = Int(s)
    if t >= 3600 && t % 3600 == 0 { return "\(t / 3600)h" }
    if t >= 60 { return "\(t / 60)m" }
    return "\(t)s"
}

func clock(_ s: Double) -> String {
    let t = max(0, Int(s.rounded(.up)))
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

func timeOfDay(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

struct Slot {
    var end: Date?
    var duration: Double = 0
    var previousEnd: Date?
    var previousDuration: Double = 0
}

enum Pomodoro {
    static let settings: [(title: String, key: String, fallback: Double, choices: [Double])] = [
        ("Focus", "pomodoroFocus", 25, [15, 20, 25, 30, 40, 45, 50, 60, 90]),
        ("Break", "pomodoroBreak", 5, [3, 5, 7, 10, 15]),
        ("Long break", "pomodoroLong", 15, [10, 15, 20, 30, 45]),
        ("Focus rounds before long break", "pomodoroRounds", 4, [2, 3, 4, 5, 6]),
    ]

    static func value(_ key: String) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : settings.first { $0.key == key }!.fallback
    }

    static let pullMarks: [Double] = settings[0].choices.map { $0 * 60 }

    static func breakMinutes(focus: Double) -> Double { focus / 5 }

    static func longMinutes(focus: Double) -> Double { focus * 3 / 5 }

    static var rounds: Int { max(Int(value("pomodoroRounds")), 1) }

    static func isFocus(_ phase: Int) -> Bool { phase % 2 == 0 }

    static func isLongBreak(_ phase: Int) -> Bool { phase % 2 == 1 && (phase / 2 + 1) % rounds == 0 }

    static func seconds(_ phase: Int) -> Double {
        value(isFocus(phase) ? "pomodoroFocus" : isLongBreak(phase) ? "pomodoroLong" : "pomodoroBreak") * 60
    }

    static func name(_ phase: Int) -> String {
        if isFocus(phase) { return "focus \(phase / 2 % rounds + 1) of \(rounds)" }
        return isLongBreak(phase) ? "long break" : "break"
    }

    static var summary: String {
        ["pomodoroFocus", "pomodoroBreak", "pomodoroLong"].map { String(format: "%g", value($0)) }.joined(separator: "/")
    }
}

enum TimerLog {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/PullTimer.log")

    static func add(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = Data((f.string(from: Date()) + "  " + text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: url)
        }
    }

    static func recent(_ count: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(count).reversed().map(String.init)
    }
}

func pullGlyph(size: CGFloat, color: NSColor) -> NSImage {
    NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
        let u = rect.width / 18
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        color.setStroke()
        color.setFill()
        let ring = NSBezierPath(ovalIn: CGRect(x: 3.75 * u, y: 5.75 * u, width: 10.5 * u, height: 10.5 * u))
        ring.lineWidth = 1.6 * u
        ring.stroke()
        let lines = NSBezierPath()
        lines.move(to: pt(9, 14))
        lines.line(to: pt(9, 11))
        lines.line(to: pt(11.3, 11))
        lines.move(to: pt(9, 5.75))
        lines.line(to: pt(9, 3.2))
        lines.lineWidth = 1.4 * u
        lines.lineCapStyle = .round
        lines.lineJoinStyle = .round
        lines.stroke()
        NSBezierPath(ovalIn: CGRect(x: 7.3 * u, y: 0.2 * u, width: 3.4 * u, height: 3.4 * u)).fill()
        return true
    }
}

func tomatoGlyph(size: CGFloat, color: NSColor?) -> NSImage {
    NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
        let u = rect.width / 18
        let body = NSBezierPath(ovalIn: CGRect(x: 2.2 * u, y: 1.2 * u, width: 13.6 * u, height: 11.8 * u))
        if let color {
            color.set()
            body.lineWidth = 1.6 * u
            body.stroke()
        } else {
            NSColor(red: 0.9, green: 0.2, blue: 0.13, alpha: 1).setFill()
            body.fill()
            NSColor(red: 0.22, green: 0.6, blue: 0.22, alpha: 1).set()
        }
        let top = CGPoint(x: 9 * u, y: 12.4 * u)
        func polar(_ degrees: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: top.x + cos(degrees * .pi / 180) * radius * u, y: top.y + sin(degrees * .pi / 180) * radius * u)
        }
        let leaves = NSBezierPath()
        for angle: CGFloat in [195, 232, 270, 308, 345] {
            leaves.move(to: top)
            leaves.line(to: polar(angle - 30, 2))
            leaves.line(to: polar(angle, 4.8))
            leaves.line(to: polar(angle + 30, 2))
            leaves.close()
        }
        leaves.fill()
        let stem = NSBezierPath()
        stem.move(to: top)
        stem.line(to: CGPoint(x: 10.2 * u, y: 16.6 * u))
        stem.lineWidth = 1.7 * u
        stem.lineCapStyle = .round
        stem.stroke()
        return true
    }
}

final class OverlayView: NSView {
    var origin = CGPoint.zero
    var backdrop: NSColor?
    var underlay: (() -> Void)?
    var timerRunning = false
    var slot = 0
    var pomodoro = false
    var showMarks = false
    private var cursor = CGPoint.zero
    private var trail: [CGPoint] = []

    private func radius(_ p: CGPoint) -> CGFloat {
        hypot(p.x - origin.x, p.y - origin.y)
    }

    func track(_ p: CGPoint) {
        cursor = p
        let d = radius(p)
        while let last = trail.last, radius(last) >= d { trail.removeLast() }
        if d - (trail.last.map(radius) ?? 0) >= 8 { trail.append(p) }
        needsDisplay = true
    }

    private func curve(to d: CGFloat) -> [CGPoint] {
        var pts = [origin]
        let dir = CGPoint(x: (cursor.x - origin.x) / d, y: (cursor.y - origin.y) / d)
        var target: CGFloat = 180
        while target < d - 90 {
            if let hit = trail.first(where: { radius($0) >= target }) {
                let along = (hit.x - origin.x) * dir.x + (hit.y - origin.y) * dir.y
                let chord = CGPoint(x: origin.x + dir.x * along, y: origin.y + dir.y * along)
                pts.append(CGPoint(x: chord.x + (hit.x - chord.x) * 0.5, y: chord.y + (hit.y - chord.y) * 0.5))
            }
            target += 180
        }
        pts.append(cursor)
        var out: [CGPoint] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            for step in 0..<16 {
                let t = CGFloat(step) / 16, t2 = t * t, t3 = t2 * t
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ e: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - e) * t2 + (3 * b - a - 3 * c + e) * t3)
                }
                out.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(cursor)
        return out
    }

    private func labelSide(_ tangent: CGPoint) -> CGPoint {
        let perp = CGPoint(x: -tangent.y, y: tangent.x)
        if perp.y > 0.01 || (abs(perp.y) <= 0.01 && perp.x > 0) {
            return CGPoint(x: -perp.x, y: -perp.y)
        }
        return perp
    }

    override func draw(_ dirtyRect: NSRect) {
        if let backdrop {
            backdrop.setFill()
            bounds.fill()
        }
        underlay?()
        let d = radius(cursor)
        guard d > 1 else { return }
        let perp = labelSide(CGPoint(x: (cursor.x - origin.x) / d, y: (cursor.y - origin.y) / d))
        let marks = pomodoro ? Pomodoro.pullMarks : Scale.marks
        let seconds = Scale.seconds(forDistance: d, marks)
        let accent = NSColor.white

        func stroke(_ points: [CGPoint], _ color: NSColor, _ width: CGFloat) {
            let p = NSBezierPath()
            p.move(to: points[0])
            for point in points.dropFirst() { p.line(to: point) }
            p.lineWidth = width
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            color.setStroke()
            p.stroke()
        }

        let path = curve(to: d)
        stroke(path, NSColor.black.withAlphaComponent(0.5), 4)
        stroke(path, seconds == nil ? NSColor.white.withAlphaComponent(0.5) : accent, 2)

        for (index, mark) in marks.enumerated() {
            let dm = Scale.distance(forSeconds: mark, marks)
            guard showMarks, dm <= d + 0.5 else { break }
            var i = path.count - 2
            if let found = (0..<(path.count - 1)).first(where: { radius(path[$0 + 1]) >= dm }) { i = found }
            let a = path[i], b = path[i + 1]
            let ra = radius(a), rb = radius(b)
            let f = rb > ra ? min(max((dm - ra) / (rb - ra), 0), 1) : 1
            let p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            let side = labelSide(CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len))
            let t0 = CGPoint(x: p.x - side.x * 3.5, y: p.y - side.y * 3.5)
            let t1 = CGPoint(x: p.x + side.x * 3.5, y: p.y + side.y * 3.5)
            stroke([t0, t1], NSColor.black.withAlphaComponent(0.5), 3)
            stroke([t0, t1], accent, 1.5)
            let label = NSAttributedString(string: short(mark), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
            let size = label.size()
            let stagger: CGFloat = index % 2 == 1 && abs(side.y) > 0.6 ? 14 : 0
            let off = 11 + stagger + abs(side.x) * size.width / 2 + abs(side.y) * size.height / 2
            pill([label], center: CGPoint(x: p.x + side.x * off, y: p.y + side.y * off), alpha: 0.8, padding: 4)
        }

        let dot = NSBezierPath(ovalIn: CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8))
        NSColor.white.setFill()
        dot.fill()

        let r: CGFloat = 15
        let knob = NSBezierPath(ovalIn: CGRect(x: cursor.x - r, y: cursor.y - r, width: 2 * r, height: 2 * r))
        NSColor(white: seconds == nil ? 0.45 : 0.1, alpha: 0.9).setFill()
        knob.fill()
        NSColor.white.setStroke()
        knob.lineWidth = 2
        knob.stroke()
        (pomodoro ? tomatoGlyph(size: 22, color: nil) : pullGlyph(size: 22, color: .white))
            .draw(in: CGRect(x: cursor.x - 11, y: cursor.y - 11, width: 22, height: 22))

        var lines: [NSAttributedString]
        if let seconds {
            lines = [
                NSAttributedString(string: spoken(seconds), attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]),
                NSAttributedString(string: "rings at " + timeOfDay(Date().addingTimeInterval(seconds)), attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
                ]),
            ]
            if pomodoro {
                let focus = seconds / 60
                let rest = String(format: "break %g min, long break %g min", Pomodoro.breakMinutes(focus: focus), Pomodoro.longMinutes(focus: focus))
                lines[1] = NSAttributedString(string: rest, attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
                ])
                lines.insert(NSAttributedString(string: "POMODORO FOCUS", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
                ]), at: 0)
            } else if slot == 1 {
                lines.insert(NSAttributedString(string: "TIMER 2", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
                ]), at: 0)
            }
        } else {
            let text = timerRunning ? "Release to cancel timer" + (slot == 1 ? " 2" : "") : "Release to cancel"
            lines = [NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])]
        }
        let w = lines.map { $0.size().width }.max()! + 28
        let h = lines.map { $0.size().height }.reduce(0, +) + 16
        let off = 34 + abs(perp.x) * w / 2 + abs(perp.y) * h / 2
        var center = CGPoint(x: cursor.x - perp.x * off, y: cursor.y - perp.y * off)
        let fits = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        if !bounds.insetBy(dx: 8, dy: 8).contains(fits) {
            center = CGPoint(x: cursor.x + perp.x * (off + 30), y: cursor.y + perp.y * (off + 30))
        }
        center.x = min(max(center.x, w / 2 + 8), bounds.width - w / 2 - 8)
        center.y = min(max(center.y, h / 2 + 8), bounds.height - h / 2 - 8)
        pill(lines, center: center, alpha: 0.85, padding: 14)
    }

    private func pill(_ lines: [NSAttributedString], center: CGPoint, alpha: CGFloat, padding: CGFloat) {
        let sizes = lines.map { $0.size() }
        let w = sizes.map(\.width).max()! + padding * 2
        let h = sizes.map(\.height).reduce(0, +) + padding * (padding > 8 ? 1.15 : 0.5)
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: min(h / 2, 12), yRadius: min(h / 2, 12)).fill()
        var y = rect.maxY - (h - sizes.map(\.height).reduce(0, +)) / 2
        for (text, size) in zip(lines, sizes) {
            y -= size.height
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: y))
        }
    }
}

final class BannerView: NSView {
    var onClick: () -> Void = {}
    private let lines: [NSAttributedString]
    private let glyph: CGFloat = 46
    private let tomato: Bool

    init(title: String, body: String, tomato: Bool = false) {
        self.tomato = tomato
        func line(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            ])
        }
        lines = [line(title, 40, .bold, 1), line(body, 16, .regular, 0.85), line("Click to dismiss", 12, .regular, 0.5)]
        let width = max(lines.map { $0.size().width }.max()! + 110, 380)
        let height = lines.map { $0.size().height }.reduce(0, +) + glyph + 84
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 26, yRadius: 26).fill()
        var y = bounds.height - 30 - glyph
        (tomato ? tomatoGlyph(size: glyph, color: nil) : pullGlyph(size: glyph, color: .white)).draw(in: CGRect(x: bounds.midX - glyph / 2, y: y, width: glyph, height: glyph))
        y -= 8
        for (index, text) in lines.enumerated() {
            let size = text.size()
            y -= size.height + (index == 2 ? 14 : 2)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y))
        }
    }
}

final class DragCatcher: NSView {
    var onDown: () -> Void = {}
    var onRightDown: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onDown()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightDown()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayView?
    private var dragOrigin = CGPoint.zero
    private var tracker: Timer?
    private var lastTrackingEnd = Date.distantPast
    private var blinker: Timer?
    private var acknowledged = false
    private var insidePress = false
    private var menuPending: Date?
    private var ticker: Timer?
    private var slots = [Slot(), Slot()]
    private var alertText: String?
    private var banner: NSPanel?
    private var pomodoro: Int?
    private var alertID = 0
    private var iconKey = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = pullGlyph(size: 18, color: .black)
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let catcher = DragCatcher(frame: button.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onDown = { [weak self] in self?.buttonPressed() }
        catcher.onRightDown = { [weak self] in self?.showMenu() }
        button.addSubview(catcher)

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let frame = self.iconFrame(),
                  frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else { return }
            self.beginTracking()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            NSLog("PullTimer icon frame: %@", String(describing: self?.iconFrame()))
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let defaults = UserDefaults.standard
        for slot in slots.indices {
            let saved = defaults.double(forKey: "endDate\(slot)")
            if saved > Date().timeIntervalSince1970 {
                slots[slot].end = Date(timeIntervalSince1970: saved)
                slots[slot].duration = defaults.double(forKey: "duration\(slot)")
            }
        }
        if slots[0].end != nil, defaults.object(forKey: "pomodoroPhase") != nil {
            pomodoro = defaults.integer(forKey: "pomodoroPhase")
        }
        refresh()
    }

    private func iconFrame() -> CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func buttonPressed() {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            insidePress = true
            beginTracking()
            while tracker != nil {
                _ = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                    until: Date().addingTimeInterval(1.0 / 60), inMode: .eventTracking, dequeue: true)
            }
            insidePress = false
        } else if blinker != nil {
            stopAlert()
        } else if let pending = menuPending, Date().timeIntervalSince(pending) < 1 {
            menuPending = nil
            showMenu()
            lastTrackingEnd = Date()
        } else if Date().timeIntervalSince(lastTrackingEnd) > 0.5 {
            showMenu()
            lastTrackingEnd = Date()
        }
    }

    private func beginTracking() {
        guard tracker == nil, let frame = iconFrame() else { return }
        if blinker != nil {
            stopAlert()
            acknowledged = true
        }
        dragOrigin = CGPoint(x: frame.midX, y: frame.midY)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.dragMoved()
            } else {
                self.tracker?.invalidate()
                self.tracker = nil
                self.dragEnded()
                self.lastTrackingEnd = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracker = timer
    }

    private func dragMoved() {
        let mouse = NSEvent.mouseLocation
        if overlayWindow == nil {
            guard hypot(mouse.x - dragOrigin.x, mouse.y - dragOrigin.y) > 12 else { return }
            showOverlay()
        }
        guard let window = overlayWindow, let view = overlayView else { return }
        view.origin = CGPoint(x: dragOrigin.x - window.frame.minX, y: dragOrigin.y - window.frame.minY)
        view.slot = pulledSlot()
        view.pomodoro = pulledPomodoro()
        view.timerRunning = slots[view.slot].end != nil
        view.track(CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY))
    }

    private func dragEnded() {
        let wasAcknowledged = acknowledged
        acknowledged = false
        guard overlayWindow != nil else {
            if wasAcknowledged { return }
            if insidePress {
                showMenu()
                return
            }
            menuPending = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.menuPending != nil else { return }
                self.menuPending = nil
                self.showMenu()
                self.lastTrackingEnd = Date()
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        let distance = hypot(mouse.x - dragOrigin.x, mouse.y - dragOrigin.y)
        let seconds = Scale.seconds(forDistance: distance)
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
        statusItem.button?.alphaValue = 1
        if pulledPomodoro() {
            if let focus = Scale.seconds(forDistance: distance, Pomodoro.pullMarks).map({ $0 / 60 }) {
                UserDefaults.standard.set(focus, forKey: "pomodoroFocus")
                UserDefaults.standard.set(Pomodoro.breakMinutes(focus: focus), forKey: "pomodoroBreak")
                UserDefaults.standard.set(Pomodoro.longMinutes(focus: focus), forKey: "pomodoroLong")
                startPomodoro()
            } else {
                cancel(0)
            }
        } else if let seconds {
            start(pulledSlot(), seconds)
        } else {
            cancel(pulledSlot())
        }
    }

    private func pulledPomodoro() -> Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private func pulledSlot() -> Int {
        NSEvent.modifierFlags.contains(.option) && !pulledPomodoro() ? 1 : 0
    }

    private func startAlert(_ title: String, _ body: String, brief: Bool = false) {
        NSSound(named: "Glass")?.play()
        alertText = title
        alertID += 1
        if brief {
            let id = alertID
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, self.alertID == id, self.blinker != nil else { return }
                self.stopAlert()
            }
        }
        blinker?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            button.animator().alphaValue = button.alphaValue > 0.6 ? 0.25 : 1
        }
        RunLoop.main.add(timer, forMode: .common)
        blinker = timer
        if !UserDefaults.standard.bool(forKey: "hideBanner") { showBanner(title, body, tomato: brief) }
    }

    private func doneText(_ slot: Int) -> String {
        "Your \(spoken(slots[slot].duration)) timer\(slot == 1 ? " (timer 2)" : "") is done."
    }

    private func showBanner(_ title: String, _ body: String, tomato: Bool) {
        banner?.orderOut(nil)
        let view = BannerView(title: title, body: body, tomato: tomato)
        view.onClick = { [weak self] in self?.stopAlert() }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(x: screen.frame.midX - view.bounds.width / 2, y: screen.frame.midY - view.bounds.height / 2)
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: view.bounds.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = view
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        banner = panel
    }

    private func stopAlert() {
        banner?.orderOut(nil)
        banner = nil
        blinker?.invalidate()
        blinker = nil
        alertText = nil
        guard let button = statusItem.button else { return }
        button.alphaValue = 1
        button.attributedTitle = NSAttributedString(string: "")
        updateTitle()
    }

    private func showOverlay() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.orderFrontRegardless()
        overlayWindow = window
        overlayView = view
        view.showMarks = UserDefaults.standard.bool(forKey: "showMarks")
        statusItem.button?.alphaValue = 0.3
    }

    private func beginPhase(_ phase: Int) {
        let seconds = Pomodoro.seconds(phase)
        pomodoro = phase
        slots[0].end = Date().addingTimeInterval(seconds)
        slots[0].duration = seconds
        TimerLog.add("pomodoro \(Pomodoro.name(phase)) started, \(spoken(seconds))")
    }

    private func start(_ slot: Int, _ seconds: Double) {
        stopAlert()
        if slot == 0 { pomodoro = nil }
        remember(slot)
        let end = Date().addingTimeInterval(seconds)
        slots[slot].end = end
        slots[slot].duration = seconds
        TimerLog.add("timer \(slot + 1) started, \(spoken(seconds)), rings at \(timeOfDay(end))")
        refresh()
    }

    private func remember(_ slot: Int) {
        guard let end = slots[slot].end else { return }
        slots[slot].previousEnd = end
        slots[slot].previousDuration = slots[slot].duration
    }

    private func cancel(_ slot: Int) {
        if slot == 0 { pomodoro = nil }
        guard let end = slots[slot].end else { return }
        remember(slot)
        slots[slot].end = nil
        TimerLog.add("timer \(slot + 1) cancelled with \(clock(end.timeIntervalSinceNow)) left")
        refresh()
    }

    private func restore(_ slot: Int) {
        guard let end = slots[slot].previousEnd, end > Date() else { return }
        let duration = slots[slot].previousDuration
        slots[slot].previousEnd = nil
        if slot == 0 { pomodoro = nil }
        remember(slot)
        slots[slot].end = end
        slots[slot].duration = duration
        TimerLog.add("timer \(slot + 1) restored, rings at \(timeOfDay(end))")
        refresh()
    }

    private func refresh() {
        let defaults = UserDefaults.standard
        for (slot, state) in slots.enumerated() {
            if let end = state.end {
                defaults.set(end.timeIntervalSince1970, forKey: "endDate\(slot)")
                defaults.set(state.duration, forKey: "duration\(slot)")
            } else {
                defaults.removeObject(forKey: "endDate\(slot)")
            }
        }
        if let pomodoro {
            defaults.set(pomodoro, forKey: "pomodoroPhase")
        } else {
            defaults.removeObject(forKey: "pomodoroPhase")
        }
        if slots.contains(where: { $0.end != nil }) {
            if ticker == nil {
                let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer, forMode: .common)
                ticker = timer
            }
        } else {
            ticker?.invalidate()
            ticker = nil
        }
        updateTitle()
    }

    private func tick() {
        var finished = false
        for slot in slots.indices {
            guard let end = slots[slot].end, end.timeIntervalSinceNow <= 0 else { continue }
            slots[slot].end = nil
            finished = true
            if slot == 0, let phase = pomodoro {
                beginPhase(phase + 1)
                let title = Pomodoro.isFocus(phase + 1) ? "Back to focus" : Pomodoro.isLongBreak(phase + 1) ? "Long break" : "Break time"
                let body = "\(spoken(slots[0].duration)), until \(timeOfDay(slots[0].end!))."
                notify(title, body)
                startAlert(title, body, brief: true)
                continue
            }
            TimerLog.add("timer \(slot + 1) finished, \(spoken(slots[slot].duration))")
            let title = slot == 0 ? "Time's up" : "Timer 2 is up"
            notify(title, doneText(slot))
            startAlert(title, doneText(slot))
        }
        if finished {
            refresh()
        } else {
            updateTitle()
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let focus = pomodoro.map { Pomodoro.isFocus($0) }
        let key = "\(String(describing: focus)) \(alertText != nil)"
        guard key != iconKey else { return }
        iconKey = key
        if let focus {
            button.image = tomatoGlyph(size: 18, color: focus ? nil : .black)
            button.image?.isTemplate = !focus
        } else {
            button.image = pullGlyph(size: 18, color: alertText != nil ? .systemOrange : .black)
            button.image?.isTemplate = alertText == nil
        }
    }

    private func updateTitle() {
        updateIcon()
        guard let button = statusItem.button else { return }
        var parts: [String] = []
        if let end = slots[0].end {
            let prefix = pomodoro.map { Pomodoro.isFocus($0) ? "focus " : "break " } ?? ""
            parts.append(prefix + clock(end.timeIntervalSinceNow))
        }
        if let end = slots[1].end { parts.append("② " + clock(end.timeIntervalSinceNow)) }
        if let alertText {
            button.attributedTitle = NSAttributedString(string: " " + ([alertText] + parts).joined(separator: "  "), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.systemOrange,
            ])
        } else {
            button.title = parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
        }
    }

    private func notify(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = title
                    alert.informativeText = body
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func showMenu() {
        let menu = NSMenu()
        func note(_ title: String, in target: NSMenu) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            target.addItem(item)
        }
        func action(_ title: String, _ selector: Selector, _ slot: Int) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.tag = slot
            menu.addItem(item)
        }
        for (slot, state) in slots.enumerated() {
            if let end = state.end {
                if slot == 0, let phase = pomodoro {
                    note("Pomodoro: \(Pomodoro.name(phase)) until \(timeOfDay(end))", in: menu)
                    action("Stop pomodoro", #selector(cancelTimer(_:)), slot)
                } else {
                    note("Timer \(slot + 1) rings at \(timeOfDay(end))", in: menu)
                    action("Cancel timer \(slot + 1)", #selector(cancelTimer(_:)), slot)
                }
            }
            if let previous = state.previousEnd, previous > Date() {
                action("Restore previous timer \(slot + 1) (rings at \(timeOfDay(previous)))", #selector(restoreTimer(_:)), slot)
            }
        }
        if !slots.contains(where: { $0.end != nil }) {
            note("Drag the icon to set a timer", in: menu)
        }
        note("Hold ⌥ while dragging for timer 2", in: menu)
        note("Hold ⇧ while dragging for a pomodoro", in: menu)
        if pomodoro == nil {
            action("Start pomodoro (\(Pomodoro.summary) min)", #selector(startPomodoro), 0)
            menu.items.last?.image = tomatoGlyph(size: 16, color: nil)
        }
        menu.addItem(.separator())
        let log = NSMenuItem(title: "Log", action: nil, keyEquivalent: "")
        let logMenu = NSMenu()
        let entries = TimerLog.recent(15)
        for entry in entries { note(entry, in: logMenu) }
        if entries.isEmpty { note("No entries yet", in: logMenu) }
        logMenu.addItem(.separator())
        logMenu.addItem(withTitle: "Open log file", action: #selector(openLog), keyEquivalent: "").target = self
        log.submenu = logMenu
        menu.addItem(log)
        let lengths = NSMenuItem(title: "Pomodoro settings", action: nil, keyEquivalent: "")
        lengths.image = tomatoGlyph(size: 16, color: nil)
        let lengthsMenu = NSMenu()
        for (index, setting) in Pomodoro.settings.enumerated() {
            if index > 0 { lengthsMenu.addItem(.separator()) }
            note(setting.title, in: lengthsMenu)
            for choice in Set(setting.choices + [Pomodoro.value(setting.key)]).sorted() {
                let unit = setting.key == "pomodoroRounds" ? "" : " min"
                let item = NSMenuItem(title: String(format: "%g", choice) + unit, action: #selector(setPomodoro(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.representedObject = choice
                item.state = Pomodoro.value(setting.key) == choice ? .on : .off
                lengthsMenu.addItem(item)
            }
        }
        lengths.submenu = lengthsMenu
        menu.addItem(lengths)
        let marks = NSMenuItem(title: "Show scale marks while pulling", action: #selector(toggleMarks), keyEquivalent: "")
        marks.target = self
        marks.state = UserDefaults.standard.bool(forKey: "showMarks") ? .on : .off
        menu.addItem(marks)
        let bannerItem = NSMenuItem(title: "Show banner mid-screen when time is up", action: #selector(toggleBanner), keyEquivalent: "")
        bannerItem.target = self
        bannerItem.state = UserDefaults.standard.bool(forKey: "hideBanner") ? .off : .on
        menu.addItem(bannerItem)
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: "Quit Pull Timer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func cancelTimer(_ sender: NSMenuItem) {
        cancel(sender.tag)
    }

    @objc private func restoreTimer(_ sender: NSMenuItem) {
        restore(sender.tag)
    }

    @objc private func startPomodoro() {
        stopAlert()
        remember(0)
        beginPhase(0)
        refresh()
    }

    @objc private func setPomodoro(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(choice, forKey: Pomodoro.settings[sender.tag].key)
        TimerLog.add("pomodoro \(Pomodoro.settings[sender.tag].title.lowercased()) set to \(String(format: "%g", choice))")
    }

    @objc private func toggleMarks() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showMarks"), forKey: "showMarks")
    }

    @objc private func toggleBanner() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "hideBanner"), forKey: "hideBanner")
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(TimerLog.url)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

if let dir = ProcessInfo.processInfo.environment["PULLTIMER_ICONSET"] {
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px)
        let plate = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
        let shape = NSBezierPath(roundedRect: plate, xRadius: s * 0.18, yRadius: s * 0.18)
        NSGradient(starting: NSColor(red: 1, green: 0.42, blue: 0.05, alpha: 1),
                   ending: NSColor(red: 1, green: 0.68, blue: 0.18, alpha: 1))!.draw(in: shape, angle: 90)
        pullGlyph(size: s * 0.56, color: .white).draw(in: CGRect(x: s * 0.22, y: s * 0.22, width: s * 0.56, height: s * 0.56))
        NSGraphicsContext.current = nil
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
    }
    exit(0)
}

if let path = ProcessInfo.processInfo.environment["PULLTIMER_BANNER"] {
    let tomato = ProcessInfo.processInfo.environment["PULLTIMER_TOMATO"] != nil
    let view = tomato ? BannerView(title: "Break time", body: "5 minutes, until 14:35.", tomato: true)
        : BannerView(title: "Time's up", body: "Your 5 minutes timer is done.")
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    if tomato {
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.8, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 150, height: 44).fill()
        tomatoGlyph(size: 18, color: nil).draw(in: CGRect(x: 8, y: 13, width: 18, height: 18))
        tomatoGlyph(size: 18, color: .black).draw(in: CGRect(x: 34, y: 13, width: 18, height: 18))
        tomatoGlyph(size: 40, color: nil).draw(in: CGRect(x: 60, y: 2, width: 40, height: 40))
        tomatoGlyph(size: 40, color: .black).draw(in: CGRect(x: 104, y: 2, width: 40, height: 40))
        NSGraphicsContext.current = nil
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    exit(0)
}

if let path = ProcessInfo.processInfo.environment["PULLTIMER_SNAPSHOT"] {
    let parts = (ProcessInfo.processInfo.environment["PULLTIMER_PULL"] ?? "-60,-420")
        .split(separator: ",").compactMap { Double($0) }
    let env = ProcessInfo.processInfo.environment
    let dims = (env["PULLTIMER_SIZE"] ?? "900x900").split(separator: "x").compactMap { Double($0) }
    let view = OverlayView(frame: CGRect(x: 0, y: 0, width: dims[0], height: dims[1]))
    let home = CGPoint(x: dims[0] - 120, y: dims[1] - 12)
    view.backdrop = NSColor(white: 0.45, alpha: 1)
    view.origin = home
    view.slot = Int(env["PULLTIMER_SLOT"] ?? "") ?? 0
    view.pomodoro = env["PULLTIMER_POMODORO"] != nil
    view.showMarks = env["PULLTIMER_MARKS"] != nil
    var title = env["PULLTIMER_RUNNING"] ?? ""
    var dim: CGFloat = 0.35
    if env["PULLTIMER_RUNNING"] != nil {
        view.underlay = {
            NSGradient(starting: NSColor(red: 0.16, green: 0.22, blue: 0.38, alpha: 1),
                       ending: NSColor(red: 0.42, green: 0.36, blue: 0.52, alpha: 1))!.draw(in: view.bounds, angle: 70)
            NSColor.black.withAlphaComponent(0.35).setFill()
            CGRect(x: 0, y: view.bounds.height - 24, width: view.bounds.width, height: 24).fill()
            pullGlyph(size: 18, color: NSColor.white.withAlphaComponent(dim))
                .draw(in: CGRect(x: home.x - 9, y: home.y - 9, width: 18, height: 18))
            NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(dim),
            ]).draw(at: CGPoint(x: home.x + 13, y: home.y - 8))
        }
    }
    func point(_ t: Double) -> CGPoint {
        let bend = sin(t * .pi) * 70
        return CGPoint(x: home.x + parts[0] * t + bend, y: home.y + parts[1] * t + bend * 0.3)
    }
    if path.hasSuffix(".gif") {
        let pullFrames = 40
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                   "com.compuserve.gif" as CFString, pullFrames + 3, nil)!
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        func frame(_ delay: Double) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(dims[0]), pixelsHigh: Int(dims[1]),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            view.cacheDisplay(in: view.bounds, to: rep)
            CGImageDestinationAddImage(dest, rep.cgImage!, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        dim = 1
        view.track(home)
        frame(1.0)
        dim = 0.35
        for step in 1...pullFrames {
            let t = Double(step) / Double(pullFrames)
            view.track(point(1 - pow(1 - t, 2.2)))
            frame(step == pullFrames ? 1.3 : 0.045)
        }
        dim = 1
        title = (env["PULLTIMER_RUNNING"] ?? "") + "  ② " + clock(Scale.seconds(forDistance: hypot(parts[0], parts[1])) ?? 0)
        view.track(home)
        frame(2.2)
        frame(0.1)
        CGImageDestinationFinalize(dest)
        exit(0)
    }
    for step in 1...60 { view.track(point(Double(step) / 60)) }
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
