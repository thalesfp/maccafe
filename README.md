# maccafe

Keep a Mac awake from the menu bar, the terminal, or over MCP, like the Caffeine
app.

maccafe takes an IOKit power assertion. By default it takes
`PreventUserIdleDisplaySleep`, which stops the display from dimming and, as a
result, stops idle system sleep too. This is what Caffeine does.

The Mac can still sleep for reasons an assertion cannot block: a closed lid, a
low battery, or a sleep you ask for from the Apple menu.

## Shape

A menu bar agent owns the assertion. The CLI and the MCP server are clients of
it, so a hold outlives whatever asked for it.

launchd starts the agent at login and again on demand, so `maccafe on` in a
fresh terminal works whether or not the icon is already there.

## Install

```
make install
```

This puts `Maccafe.app` in `/Applications`, registers the agent as a login item,
and links the CLI into `/usr/local/bin`. The link is the only step that needs
`sudo`.

macOS asks you to approve the agent the first time. It appears in System
Settings under General, Login Items, "Allow in the Background".

Run `make` on its own to list every target.

## Use

Click the menu bar icon to turn the hold on or off, pick a duration, or let the
display sleep while the system stays up.

From the terminal:

```
maccafe on                      # stay awake until you turn it off
maccafe on --duration 2h        # stay awake for two hours
maccafe on --system-only        # let the display sleep, keep the system up
maccafe off
maccafe status
```

Durations read as `45s`, `90m`, `2h`, `1h30m`, or a plain number of seconds.

Running `on` again replaces the current hold. Only one hold exists at a time, so
`maccafe status` always describes the whole picture.

Quitting from the menu releases the hold and removes the icon. It comes back at
the next login, or as soon as any command needs the agent.

## Scripting

`on`, `off`, and `status` take `--json`, so a script or an agent does not have to
read prose. Output goes to stdout, including on failure. The exit code is 0 for
success, 1 for a failure while running, and 64 for a bad argument; all three
shapes are JSON when the flag is present.

```
$ maccafe on --duration 90m --json
{"elapsed_seconds":0,"expires_at":"2026-08-20T02:05:23Z","held":true,
 "kind":"display","remaining_seconds":5400,"started_at":"2026-08-20T00:35:23Z"}

$ maccafe status --json
{"held":false}

$ maccafe off --json
{"held":false,"stopped":true}

$ maccafe status --json     # after a failure
{"error":"..."}
```

`expires_at` and `remaining_seconds` are null for a hold with no time limit.
Timestamps are RFC 3339 in UTC. The seconds are derived from the timestamps when
the report is printed, so they are always current.

## MCP

`maccafe mcp` serves three tools over stdio: `caffeine_on`, `caffeine_off`, and
`caffeine_status`. They return the same JSON the `--json` flag prints. The hold
lives in the agent, so it outlives the client disconnecting.

```
claude mcp add maccafe -- maccafe mcp
```

## State

None on disk. The agent holds the assertion in memory, so nothing can outlive it
and no file can claim a hold that is not real. `pmset -g assertions` shows the
truth at any moment.

## License

MIT. See [LICENSE](LICENSE).
