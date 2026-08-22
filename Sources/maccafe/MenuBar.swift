import AppKit

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let presets: [(title: String, seconds: Int?)] = [
        ("Until turned off", nil),
        ("15 minutes", 900),
        ("1 hour", 3_600),
        ("2 hours", 7_200),
        ("4 hours", 14_400),
    ]

    private let agent: Agent
    private var item: NSStatusItem?
    private var gauge: Timer?
    private var preferredSystemOnly = false

    init(agent: Agent) {
        self.agent = agent
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        self.item = item

        agent.observe { [weak self] in
            Task { @MainActor in self?.draw() }
        }
    }

    /// The running hold is the only source of truth for the kind, so the menu
    /// remembers what it last saw rather than keeping a rival preference.
    private func draw() {
        let hold = agent.hold

        if let hold {
            preferredSystemOnly = hold.kind == .system
        }

        let reading = Gauge.reading(for: hold, at: Date())

        item?.button?.image = CupGlyph.image(step: reading.step)

        rearmGauge(at: reading.changesAt)
    }

    /// The gauge wakes when the drawn step changes rather than on a tick, so a
    /// whole hold costs a handful of redraws and an idle agent costs none.
    private func rearmGauge(at moment: Date?) {
        gauge?.invalidate()
        gauge = nil

        guard let moment else { return }

        gauge = Timer.scheduledTimer(
            withTimeInterval: max(1, moment.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.draw()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let hold = agent.hold
        let now = Date()

        menu.removeAllItems()
        menu.addItem(header(hold, at: now))
        menu.addItem(.separator())
        menu.addItem(toggle(hold))
        menu.addItem(.separator())
        menu.addItem(durations(hold))
        menu.addItem(displaySleep())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "About MacCafe", action: #selector(about), keyEquivalent: "")
                .targeted(to: self)
        )
        menu.addItem(
            NSMenuItem(title: "Quit MacCafe", action: #selector(quit), keyEquivalent: "q")
                .targeted(to: self)
        )
    }

    private func header(_ hold: Hold?, at now: Date) -> NSMenuItem {
        guard let hold else {
            return NSMenuItem(title: "This Mac can sleep normally", action: nil, keyEquivalent: "")
        }

        let left =
            hold.remaining(at: now).map { "\(DurationText.format($0)) left" } ?? "no time limit"

        return NSMenuItem(title: "Keeping awake · \(left)", action: nil, keyEquivalent: "")
    }

    private func toggle(_ hold: Hold?) -> NSMenuItem {
        NSMenuItem(
            title: hold == nil ? "Turn on" : "Turn off",
            action: hold == nil ? #selector(turnOn) : #selector(turnOff),
            keyEquivalent: ""
        )
        .targeted(to: self)
    }

    private func durations(_ hold: Hold?) -> NSMenuItem {
        let submenu = NSMenu()

        for (index, preset) in Self.presets.enumerated() {
            let entry = NSMenuItem(
                title: preset.title,
                action: #selector(choose(_:)),
                keyEquivalent: ""
            )
            .targeted(to: self)
            entry.tag = index
            entry.state = hold.map { spans(preset.seconds, $0) } == true ? .on : .off
            submenu.addItem(entry)
        }

        let item = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
        item.submenu = submenu

        return item
    }

    private func spans(_ seconds: Int?, _ hold: Hold) -> Bool {
        hold.expiresAt.map { Int($0.timeIntervalSince(hold.startedAt).rounded()) } == seconds
    }

    private func displaySleep() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Allow display sleep",
            action: #selector(toggleDisplaySleep),
            keyEquivalent: ""
        )
        .targeted(to: self)

        item.state = preferredSystemOnly ? .on : .off

        return item
    }

    @objc private func turnOn() {
        _ = agent.handle(.on(seconds: nil, systemOnly: preferredSystemOnly))
    }

    @objc private func turnOff() {
        _ = agent.handle(.off)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        _ = agent.handle(
            .on(seconds: Self.presets[sender.tag].seconds, systemOnly: preferredSystemOnly)
        )
    }

    @objc private func toggleDisplaySleep() {
        preferredSystemOnly.toggle()

        agent.change(to: .forSystemOnly(preferredSystemOnly))
    }

    /// An accessory app is never the active one, so the panel would open behind
    /// whatever is in front unless the app asks for the front first.
    @objc private func about() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                .credits: NSAttributedString(
                    string: "Keeps this Mac awake with an IOKit power assertion.",
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                )
            ]
        )
    }

    @objc private func quit() {
        _ = agent.handle(.off)
        NSApplication.shared.terminate(nil)
    }
}

extension NSMenuItem {
    fileprivate func targeted(to target: AnyObject) -> NSMenuItem {
        self.target = target

        return self
    }
}
