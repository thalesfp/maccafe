# maccafe

A macOS menu bar agent that keeps the Mac awake with an IOKit power assertion,
with a CLI and an MCP server as clients of it.

## Shape

One executable, three personalities, all inside `MacCafe.app`:

- `maccafe agent` is the menu bar app. launchd starts it. It owns the assertion.
- `maccafe on|off|status` are clients that talk to the agent over XPC.
- `maccafe mcp` is a stdio MCP server that is itself a client of the agent.

## Invariants

Rules that are not obvious from any single file. Break one and the tool lies
about whether the Mac is awake, or the agent will not start at all.

- **The agent is the only holder.** It owns the IOKit assertion in memory.
  Nothing else takes one.
- **Binding the Mach service is the exclusivity mechanism.** launchd only
  guarantees one agent that launchd itself started, so `maccafe agent` typed in
  a terminal must fail. It does: `XPCListener` cannot bind a name that is
  already bound, and the agent exits non-zero.
- **No files.** There is no state file and no lock. Restarting the agent
  releases the assertion, so anything written down could only lie.
  `pmset -g assertions` is the ground truth.
- **The kernel cleans up.** The assertion dies with the agent.
- **A hold outlives the client that asked for it.** Every hold is detached.
- **The XPC handler must never block on the main thread.** The main thread is
  parked inside `NSApplication.run()` for the life of the agent, so a
  `DispatchQueue.main.sync` from the listener queue deadlocks. The agent state
  lives behind a `Mutex` for exactly this reason, and the menu bar is updated
  one-way with a hop onto the main actor.
- **The agent must own the process main thread.** `NSApplication.run()` is
  entered from a synchronous `main`, not from inside a main-actor job: entering
  it from a job leaves the main queue undrained and the menu bar never redraws.
  That is why nothing in `CLI.swift` is `async` and the one async subcommand,
  `mcp`, waits on a task through `blocking`.
- **`SMAppService` resolves the service against `Bundle.main`.** Only the copy
  of the app that holds the registration can see or remove it; any other copy
  reads `.notRegistered`. That is why `make install` and `make uninstall` run
  the *installed* binary to unregister, never the staged one.
- **launchd pins the code signature it saw at registration.** A bundle replaced
  in place is killed as a launch constraint violation (`EX_CONFIG`, SIGKILL,
  code signature invalid). Renewing the pin needs the `unregister` to run in an
  *earlier process* than the `register`; doing both inside one process re-pins
  the stale signature. `make install` runs them as two invocations.
- **`PreventUserIdleDisplaySleep` is the default** because it also blocks idle
  system sleep. `--system-only` is the narrower assertion.
- **Nothing survives a closed lid**, low battery, or a requested sleep. That is
  the platform, not a bug.

## Modules

| File | Owns |
|---|---|
| `Sources/maccafe/Assertion.swift` | The IOKit assertion, released on `deinit` |
| `Sources/maccafe/HoldState.swift` | The pure core: `Action`, `Effect`, `apply` |
| `Sources/maccafe/Wire.swift` | The `Codable` shape shared by XPC, `--json`, and MCP |
| `Sources/maccafe/Render.swift` | Prose and JSON reports, and the seconds derived from the dates |
| `Sources/maccafe/Duration.swift` | Parsing and formatting `45s`, `90m`, `1h30m` |
| `Sources/maccafe/Agent.swift` | The `XPCListener`, the effect executor, and the deadline timer |
| `Sources/maccafe/Gauge.swift` | The pure gauge: which step the cup is drawn at, and when that changes |
| `Sources/maccafe/CupGlyph.swift` | The drawn menu bar glyph, a template image at each gauge step |
| `Sources/maccafe/MenuBar.swift` | The `NSStatusItem` and its menu |
| `Sources/maccafe/Client.swift` | The `XPCSession` client and the `SMAppService` installer |
| `Sources/maccafe/MCPServer.swift` | The stdio MCP server: `caffeine_on`, `caffeine_off`, `caffeine_status` |
| `Sources/maccafe/Service.swift` | The bundle identifier, the Mach service name, and the plist name |
| `Sources/maccafe/CLI.swift` | The ArgumentParser surface and the entry point |
| `Resources/Info.plist` | `LSUIElement`, so the agent has no Dock icon |
| `Resources/me.thales.maccafe.agent.plist` | `MachServices` for on-demand start, `RunAtLoad` for the icon at login, and no `KeepAlive` so Quit works |

## Commands

```
make            # list every target
make verify     # format check, warnings as errors, tests: the gate
make bundle     # assemble MacCafe.app
make install    # install to /Applications, register the agent, link the CLI
make uninstall
make run ARGS="status"
```

`make install` needs `sudo` for the `/usr/local/bin` symlink only. Registration
stays unprivileged: a user agent registered as root lands in the wrong domain.

## Conventions

- Decision logic stays pure and takes values, not handles, so it tests without
  IOKit, XPC, or AppKit. `apply`, `Render`, and `DurationText` follow this. The
  agent is the shell that runs the `Effect` the core returned. Keep new logic on
  that side of the line.
- Tests are named for the behavior a caller relies on, not the function under
  test. swift-testing, so the name is a display string.
- Do not add a dependency without asking. There are two: `swift-argument-parser`
  and the official MCP `swift-sdk`.
- `--json` is declared only on the commands that print a report, so `mcp`,
  `install`, `uninstall`, and `agent` reject it as an unknown option rather than
  needing a runtime check. `Entry.fail` renders ArgumentParser's own errors
  through `Render.failure` too, so `--json` holds for a mistyped argument
  (exit 64), not only for a runtime failure (exit 1). Rendering the failure has
  to know the flag before parsing can succeed, so `Entry.reportingCommands`
  names that list; a new subcommand that prints a report has to join it.
- One failure path. The agent answers in-band with `Reply.failure`,
  `Client.send` turns that into a thrown `Failure`, and the CLI renders it
  through `Render.failure`. MCP turns the same throw into a JSON-RPC error,
  which is that protocol's own shape.
- The wire type and the reported type are the same type on purpose. Both sides
  ship in one binary from one build, so there is no skew to protect against.
  `elapsed_seconds` and `remaining_seconds` are derived at render time, never
  transmitted.
