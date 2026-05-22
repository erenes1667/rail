//
//  Rail.swift
//  Stripped-down Amphetamine for Apple Silicon Macs.
//
//  Right-click pill → toggle ON / OFF (one-shot inject + flex animation)
//  Left-click pill  → open options menu (stays open until click-away or logo re-click)
//  Active state     → buff bicep stays in menu bar
//

import Cocoa
import IOKit.pwr_mgt

// MARK: - Persisted Settings

enum SettingsKey {
    static let allowDisplaySleep  = "rail.allowDisplaySleep"
    static let allowLidCloseSleep = "rail.allowLidCloseSleep"
    static let allowScreenSaver   = "rail.allowScreenSaver"
}

// MARK: - Sleep Controller

final class SleepController {
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var screenSaverKeepAlive: Timer?
    private(set) var isActive = false

    private let defaults = UserDefaults.standard

    var allowDisplaySleep: Bool {
        get { defaults.bool(forKey: SettingsKey.allowDisplaySleep) }
        set { defaults.set(newValue, forKey: SettingsKey.allowDisplaySleep) }
    }
    var allowLidCloseSleep: Bool {
        get { defaults.bool(forKey: SettingsKey.allowLidCloseSleep) }
        set { defaults.set(newValue, forKey: SettingsKey.allowLidCloseSleep) }
    }
    var allowScreenSaver: Bool {
        get { defaults.bool(forKey: SettingsKey.allowScreenSaver) }
        set { defaults.set(newValue, forKey: SettingsKey.allowScreenSaver) }
    }

    func activate() {
        guard !isActive else { return }

        IOPMAssertionCreateWithName(
            "PreventUserIdleSystemSleep" as CFString,
            UInt32(kIOPMAssertionLevelOn),
            "Rail: keep system awake" as CFString,
            &systemAssertion
        )

        if !allowDisplaySleep {
            IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                UInt32(kIOPMAssertionLevelOn),
                "Rail: keep display awake" as CFString,
                &displayAssertion
            )
        }

        if !allowLidCloseSleep {
            runPmset(disableSleep: 1)
        }

        if !allowScreenSaver {
            startScreenSaverKeepAlive()
        }

        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        if systemAssertion  != 0 { IOPMAssertionRelease(systemAssertion);  systemAssertion  = 0 }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        screenSaverKeepAlive?.invalidate(); screenSaverKeepAlive = nil
        runPmset(disableSleep: 0)
        isActive = false
    }

    /// Re-apply with current settings (called when a checkbox toggles while active).
    func refresh() {
        if isActive { deactivate(); activate() }
    }

    private func startScreenSaverKeepAlive() {
        screenSaverKeepAlive?.invalidate()
        screenSaverKeepAlive = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            var id: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity(
                "Rail: keep user idle counter at 0" as CFString,
                kIOPMUserActiveLocal,
                &id
            )
        }
    }

    private func runPmset(disableSleep value: Int) {
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments  = ["-n", "pmset", "-a", "disablesleep", String(value)]
        try? task.run()
    }
}

// MARK: - Icon Renderer

enum IconRenderer {

    // MARK: Inactive — sleeping pill, slightly tilted

    static func inactive() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img  = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        let xform = NSAffineTransform()
        xform.translateX(by: 11, yBy: 11)
        xform.rotate(byDegrees: -30)
        xform.translateX(by: -11, yBy: -11)
        xform.concat()

        NSColor.black.setStroke()
        let pill = NSBezierPath(roundedRect: NSRect(x: 4, y: 8, width: 14, height: 6),
                                xRadius: 3, yRadius: 3)
        pill.lineWidth = 1.5
        pill.stroke()

        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 11, y: 8))
        divider.line(to: NSPoint(x: 11, y: 14))
        divider.lineWidth = 1.0
        divider.stroke()

        img.isTemplate = true
        return img
    }

    // MARK: Active static — comedically buff bicep with a sparkle

    static func activeStatic() -> NSImage {
        return drawArm(biceps: 1.0, sparkleCount: 1, syringeAlpha: 0, plunger: 0, dripScale: 0)
    }

    // MARK: One-shot animation frame (progress 0 → 1)
    //   0.00 - 0.50  inject (plunger pushes, liquid empties)
    //   0.50 - 0.60  hold + drip
    //   0.60 - 0.75  syringe yanks out (rises and fades)
    //   0.75 - 1.00  bicep FLEX POP with sparkles
    static func animationFrame(progress: CGFloat) -> NSImage {
        let p = max(0, min(1, progress))

        if p < 0.50 {
            let local = p / 0.50
            return drawArm(biceps: 0.0,
                          sparkleCount: 0,
                          syringeAlpha: 1.0,
                          syringeOffsetY: 0,
                          plunger: local,
                          dripScale: 0)
        }
        if p < 0.60 {
            let local = (p - 0.50) / 0.10
            // small drip + tiny jiggle
            let jitter: CGFloat = sin(local * .pi * 6) * 0.4
            return drawArm(biceps: 0.0,
                          sparkleCount: 0,
                          syringeAlpha: 1.0,
                          syringeOffsetY: jitter,
                          plunger: 1.0,
                          dripScale: local)
        }
        if p < 0.75 {
            let local = (p - 0.60) / 0.15
            return drawArm(biceps: 0.0,
                          sparkleCount: 0,
                          syringeAlpha: 1.0 - local,
                          syringeOffsetY: local * 9,
                          plunger: 1.0,
                          dripScale: 1.0 - local)
        }
        // Flex pop with overshoot
        let local = (p - 0.75) / 0.25
        let eased = 1 - pow(1 - local, 3)
        // Slight overshoot bounce in last 30%
        let overshoot: CGFloat = local > 0.7 ? sin((local - 0.7) / 0.3 * .pi) * 0.08 : 0
        let biceps = min(1.0, eased + overshoot)
        let sparkles = local > 0.45 ? 3 : (local > 0.25 ? 1 : 0)
        return drawArm(biceps: biceps,
                      sparkleCount: sparkles,
                      syringeAlpha: 0,
                      syringeOffsetY: 0,
                      plunger: 1.0,
                      dripScale: 0)
    }

    // MARK: Master drawing routine

    /// - biceps: 0 = slim, 1 = comedically buff
    /// - sparkleCount: 0...3
    /// - syringeAlpha: 0 = hidden, 1 = full
    /// - syringeOffsetY: vertical offset for retraction
    /// - plunger: 0 = full liquid, 1 = pushed in fully
    /// - dripScale: 0...1 size of drip below needle
    static func drawArm(biceps: CGFloat,
                       sparkleCount: Int,
                       syringeAlpha: CGFloat,
                       syringeOffsetY: CGFloat = 0,
                       plunger: CGFloat,
                       dripScale: CGFloat) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img  = NSImage(size: size)
        img.lockFocus()
        defer { img.isTemplate = true; img.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // -- Forearm + bicep bump ----------------------------------------
        // Forearm is the horizontal base; bicep bump scales with `biceps`.
        let armPath = NSBezierPath()
        armPath.move(to: NSPoint(x: 1, y: 5))
        // forearm out to wrist
        armPath.line(to: NSPoint(x: 22, y: 5))
        armPath.lineWidth    = 3.0
        armPath.lineCapStyle = .round
        armPath.stroke()

        // Bicep bump — curves up from the elbow region
        let bumpHeight: CGFloat = 4 + biceps * 6  // 4 slim, 10 buff
        let bumpWidth:  CGFloat = 10 + biceps * 2
        let bumpStart = NSPoint(x: 3, y: 5)
        let bumpEnd   = NSPoint(x: 3 + bumpWidth, y: 5)
        let bump = NSBezierPath()
        bump.move(to: bumpStart)
        bump.curve(to: bumpEnd,
                   controlPoint1: NSPoint(x: bumpStart.x + bumpWidth * 0.25, y: 5 + bumpHeight),
                   controlPoint2: NSPoint(x: bumpStart.x + bumpWidth * 0.75, y: 5 + bumpHeight))
        bump.lineWidth = 1.5 + biceps * 0.8
        bump.stroke()

        // Buff-state extra: tiny bicep crease line
        if biceps > 0.6 {
            let crease = NSBezierPath()
            crease.move(to: NSPoint(x: bumpStart.x + bumpWidth * 0.4, y: 5 + bumpHeight * 0.55))
            crease.line(to: NSPoint(x: bumpStart.x + bumpWidth * 0.6, y: 5 + bumpHeight * 0.55))
            crease.lineWidth = 0.8
            crease.stroke()
        }

        // -- Syringe -----------------------------------------------------
        if syringeAlpha > 0.01 {
            ctx.saveGState()
            ctx.setAlpha(syringeAlpha)
            // Anchor needle tip ~ bicep apex
            let tipX: CGFloat = bumpStart.x + bumpWidth * 0.5
            let tipY: CGFloat = 5 + bumpHeight * 0.85 + syringeOffsetY
            ctx.translateBy(x: tipX, y: tipY)
            ctx.rotate(by: .pi / 4) // 45° tilt up-right

            // Needle (short stub from tip)
            let needle = NSBezierPath()
            needle.move(to: NSPoint(x: 0, y: 0))
            needle.line(to: NSPoint(x: 2.5, y: 0))
            needle.lineWidth = 1.0
            needle.stroke()

            // Barrel
            let barrelLen: CGFloat = 8
            let barrel = NSBezierPath(rect: NSRect(x: 2.5, y: -2, width: barrelLen, height: 4))
            barrel.lineWidth = 1.0
            barrel.stroke()

            // Liquid (cocaine) — fills near needle end, shrinks as plunger pushes
            let liquidWidth = (1.0 - plunger) * (barrelLen - 1.0)
            if liquidWidth > 0.4 {
                let liquid = NSBezierPath(rect: NSRect(x: 3.0, y: -1.5, width: liquidWidth, height: 3))
                liquid.fill()
            }

            // Plunger piston + rod + thumb plate
            let pistonX = 2.5 + barrelLen - plunger * (barrelLen - 1.0)
            let rod = NSBezierPath()
            rod.move(to: NSPoint(x: pistonX, y: 0))
            rod.line(to: NSPoint(x: pistonX + 3, y: 0))
            rod.lineWidth = 0.8
            rod.stroke()
            let thumb = NSBezierPath()
            thumb.move(to: NSPoint(x: pistonX + 3, y: -3))
            thumb.line(to: NSPoint(x: pistonX + 3, y: 3))
            thumb.lineWidth = 1.8
            thumb.stroke()

            ctx.restoreGState()
        }

        // -- Drip below needle (during pause) ----------------------------
        if dripScale > 0.05 {
            let tipX: CGFloat = bumpStart.x + bumpWidth * 0.5
            let tipY: CGFloat = 5 + bumpHeight * 0.85 + syringeOffsetY
            let d = NSBezierPath(ovalIn: NSRect(x: tipX - 0.8,
                                                y: tipY - 2 - dripScale * 1.5,
                                                width: 1.5 * dripScale + 0.4,
                                                height: 1.8 * dripScale + 0.4))
            d.fill()
        }

        // -- Sparkles around the buff bicep ------------------------------
        if sparkleCount > 0 {
            // Three sparkle positions, drawn outward from the bicep peak.
            let apex = NSPoint(x: bumpStart.x + bumpWidth * 0.5,
                               y: 5 + bumpHeight + 1)
            let spots: [NSPoint] = [
                NSPoint(x: apex.x - 5, y: apex.y + 2),
                NSPoint(x: apex.x + 5, y: apex.y + 1),
                NSPoint(x: apex.x,     y: apex.y + 4),
            ]
            for i in 0..<min(sparkleCount, spots.count) {
                drawSparkle(at: spots[i], size: 2.0)
            }
        }

        return img
    }

    private static func drawSparkle(at point: NSPoint, size: CGFloat) {
        let s = NSBezierPath()
        // 4-point sparkle (vertical + horizontal cross)
        s.move(to: NSPoint(x: point.x - size, y: point.y))
        s.line(to: NSPoint(x: point.x + size, y: point.y))
        s.move(to: NSPoint(x: point.x, y: point.y - size))
        s.line(to: NSPoint(x: point.x, y: point.y + size))
        s.lineWidth    = 0.8
        s.lineCapStyle = .round
        s.stroke()
    }
}

// MARK: - Icon Animator (one-shot inject, then continuous flex pulse)

final class IconAnimator {
    weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var startedAt: Date?
    private let injectDurationSec: TimeInterval = 1.7
    private(set) var isPlaying = false

    /// Phase: .inject (one-shot), .flexing (continuous pulse), .idle.
    private enum Phase { case idle, inject, flexing }
    private var phase: Phase = .idle

    /// Plays the inject-and-flex animation once, then enters a continuous "flex pulse" loop until cancel().
    func playOnceThenFlex(on button: NSStatusBarButton) {
        cancel()
        self.button    = button
        self.startedAt = Date()
        self.phase     = .inject
        self.isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self,
                  let btn = self.button,
                  let start = self.startedAt else { return }
            let elapsed = Date().timeIntervalSince(start)

            switch self.phase {
            case .inject:
                let progress = CGFloat(min(1.0, elapsed / self.injectDurationSec))
                btn.image = IconRenderer.animationFrame(progress: progress)
                if progress >= 1.0 {
                    // Transition into flex pulse — keep timer alive, reset clock.
                    self.phase     = .flexing
                    self.startedAt = Date()
                }
            case .flexing:
                // Sine-wave pulse between 0.78 and 1.05 with overshoot.
                // Period ~2.4s. Sparkles peak at apex.
                let period: Double = 2.4
                let t = elapsed.truncatingRemainder(dividingBy: period) / period  // 0...1
                // Asymmetric: quick flex up, slow release (more "POSE" energy)
                let phase: Double = t < 0.35
                    ? sin(t / 0.35 * .pi / 2)              // fast ramp to peak (ease-out)
                    : 1.0 - (t - 0.35) / 0.65 * 0.5        // long slow release to mid (0.5)
                let biceps = CGFloat(0.78 + phase * 0.27)  // 0.78 ... ~1.05
                // Sparkles fire briefly at the apex
                let sparkles: Int = (t > 0.20 && t < 0.45) ? 3
                                 : (t > 0.08 && t < 0.55) ? 1
                                 : 0
                btn.image = IconRenderer.drawArm(biceps: biceps,
                                                 sparkleCount: sparkles,
                                                 syringeAlpha: 0,
                                                 syringeOffsetY: 0,
                                                 plunger: 1.0,
                                                 dripScale: 0)
            case .idle:
                break
            }
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        startedAt = nil
        phase     = .idle
        isPlaying = false
    }
}

// MARK: - App Controller

final class AppController: NSObject, NSMenuDelegate, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let sleeper    = SleepController()
    let animator   = IconAnimator()

    private(set) var isOn = false
    private var endDate: Date?
    private var expireTimer: Timer?

    private let presetDurations: [(String, TimeInterval)] = [
        ("5 minutes",  5  * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour",     60 * 60),
        ("2 hours",  2 * 60 * 60),
        ("5 hours",  5 * 60 * 60),
    ]

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image  = IconRenderer.inactive()
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Belt-and-suspenders cleanup: also reset pmset on unclean exits
        // (Ctrl-C, force-quit). IOPMAssertions auto-release, but
        // `pmset disablesleep` is a system-wide flag that persists.
        atexit_b {
            let task = Process()
            task.launchPath = "/usr/bin/sudo"
            task.arguments  = ["-n", "pmset", "-a", "disablesleep", "0"]
            try? task.run()
            task.waitUntilExit()
        }
    }

    // MARK: NSApplicationDelegate — clean cleanup on Quit
    func applicationWillTerminate(_ notification: Notification) {
        if isOn { turnOff() }
        // Force a final reset in case turnOff didn't fire (e.g., state desync)
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments  = ["-n", "pmset", "-a", "disablesleep", "0"]
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: Click routing
    // LEFT click  → open menu
    // RIGHT click → toggle (with animation)
    @objc func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
                   || event?.modifierFlags.contains(.control) == true
        if isRight { toggle() } else { showMenu() }
    }

    @objc func toggle() {
        if isOn { turnOff() } else { turnOn(duration: nil) }
    }

    func turnOn(duration: TimeInterval?) {
        if isOn { turnOff() }
        sleeper.activate()
        if let btn = statusItem.button {
            animator.playOnceThenFlex(on: btn)
        }
        isOn    = true
        endDate = duration.map { Date().addingTimeInterval($0) }
        expireTimer?.invalidate()
        if let d = duration {
            expireTimer = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { [weak self] _ in
                self?.turnOff()
            }
        }
    }

    func turnOff() {
        sleeper.deactivate()
        animator.cancel()
        statusItem.button?.image = IconRenderer.inactive()
        isOn    = false
        endDate = nil
        expireTimer?.invalidate(); expireTimer = nil
    }

    // MARK: Menu (left-click) — stays open until click-away or logo re-click

    func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        // Reset on next runloop tick so future left-clicks rebuild the menu.
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // Header
        let headerTitle: String
        if isOn {
            if let end = endDate {
                let remain = max(0, Int(end.timeIntervalSinceNow))
                headerTitle = "Active — \(formatRemaining(remain)) left"
            } else {
                headerTitle = "Active — indefinite"
            }
        } else {
            headerTitle = "Off"
        }
        let hdr = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        hdr.isEnabled = false
        menu.addItem(hdr)

        let hint = NSMenuItem(title: "  right-click pill to toggle quickly",
                             action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let toggleTitle = isOn ? "Turn Off" : "Turn On (indefinite)"
        let toggleItem  = NSMenuItem(title: toggleTitle, action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Timer presets
        let timerHdr = NSMenuItem(title: "Activate for…", action: nil, keyEquivalent: "")
        timerHdr.isEnabled = false
        menu.addItem(timerHdr)
        for (label, seconds) in presetDurations {
            let item = NSMenuItem(title: "  " + label,
                                  action: #selector(durationSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            menu.addItem(item)
        }
        let custom = NSMenuItem(title: "  Custom…",
                                action: #selector(customDuration),
                                keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)

        menu.addItem(.separator())

        // Persistent checkboxes (mirror Amphetamine layout)
        let optsHdr = NSMenuItem(title: "When active", action: nil, keyEquivalent: "")
        optsHdr.isEnabled = false
        menu.addItem(optsHdr)

        let d = NSMenuItem(title: "  Allow display sleep",
                          action: #selector(toggleAllowDisplaySleep),
                          keyEquivalent: "")
        d.target = self
        d.state  = sleeper.allowDisplaySleep ? .on : .off
        menu.addItem(d)

        let l = NSMenuItem(title: "  Allow system sleep when lid is closed",
                          action: #selector(toggleAllowLidCloseSleep),
                          keyEquivalent: "")
        l.target = self
        l.state  = sleeper.allowLidCloseSleep ? .on : .off
        menu.addItem(l)

        let s = NSMenuItem(title: "  Allow screen saver after 45m of inactivity",
                          action: #selector(toggleAllowScreenSaver),
                          keyEquivalent: "")
        s.target = self
        s.state  = sleeper.allowScreenSaver ? .on : .off
        menu.addItem(s)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Rail",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return       String(format: "%ds", s)
    }

    @objc func durationSelected(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        turnOn(duration: secs)
    }

    @objc func customDuration() {
        let alert = NSAlert()
        alert.messageText = "Activate Rail for how many minutes?"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "60"
        alert.accessoryView = input
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let mins = Double(input.stringValue), mins > 0 {
            turnOn(duration: mins * 60)
        }
    }

    @objc func toggleAllowDisplaySleep() {
        sleeper.allowDisplaySleep.toggle()
        sleeper.refresh()
    }

    @objc func toggleAllowLidCloseSleep() {
        sleeper.allowLidCloseSleep.toggle()
        sleeper.refresh()
    }

    @objc func toggleAllowScreenSaver() {
        sleeper.allowScreenSaver.toggle()
        sleeper.refresh()
    }
}

// MARK: - main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller   // so applicationWillTerminate fires on Quit
app.run()
