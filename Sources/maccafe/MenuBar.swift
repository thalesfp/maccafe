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

    private static let idleIcon = NSImage(
        systemSymbolName: "cup.and.saucer",
        accessibilityDescription: "maccafe: off"
    )
    private static let holdingIcon = NSImage(
        systemSymbolName: "cup.and.saucer.fill",
        accessibilityDescription: "maccafe: on"
    )

    private let agent: Agent
    private var item: NSStatusItem?
    private var preferredSystemOnly = false

    init(agent: Agent) {
        self.agent = agent
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        self.item = item

        agent.observe { [weak self] hold in
            Task { @MainActor in self?.draw(hold) }
        }
    }

    /// The running hold is the only source of truth for the kind, so the menu
    /// remembers what it last saw rather than keeping a rival preference.
    private func draw(_ hold: Hold?) {
        if let hold {
            preferredSystemOnly = hold.kind == .system
        }

        item?.button?.image = hold == nil ? Self.idleIcon : Self.holdingIcon
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
            NSMenuItem(title: "Quit Maccafe", action: #selector(quit), keyEquivalent: "q")
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
