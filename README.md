# maccafe

Keep a Mac awake from the terminal or over MCP, like the Caffeine app.

maccafe takes an IOKit power assertion. By default it takes
`PreventUserIdleDisplaySleep`, which stops the display from dimming and, as a
result, stops idle system sleep too. This is what Caffeine does.

The Mac can still sleep for reasons an assertion cannot block: a closed lid, a
low battery, or a sleep you ask for from the Apple menu.

## Install

```
make install
```

This puts the binary in `~/.cargo/bin`. Add that directory to your `PATH` if it
is not there yet.

Run `make` on its own to list every target.

## Use

```
maccafe on                      # stay awake until you turn it off
maccafe on --duration 2h        # stay awake for two hours
maccafe on --system-only        # let the display sleep, keep the system up
maccafe off
maccafe status

maccafe run --duration 45m      # hold in the foreground until Ctrl-C
maccafe run -- make release     # hold while the command runs, exit with its code
```

Durations read as `45s`, `90m`, `2h`, `1h30m`, or a plain number of seconds.

`maccafe on` starts a small background process that holds the assertion and
exits on `maccafe off` or when the duration runs out. Running `on` again
replaces the current hold. `maccafe run` refuses to start while a hold is
already in place.

Only one hold exists at a time, so `maccafe status` always describes the whole
picture.

## Scripting

Every command except `run` takes `--json`, so a script or an agent does not have
to read prose. Output goes to stdout, including on failure, and the exit code is
0 for success and 1 for failure.

```
$ maccafe --json on --duration 90m
{"held":true,"kind":"display","pid":49061,"started_at":"2026-08-20T00:35:23Z",
 "expires_at":"2026-08-20T02:05:23Z","elapsed_seconds":0,"remaining_seconds":5400}

$ maccafe --json status
{"held":false}

$ maccafe --json off
{"held":false,"stopped":true}

$ maccafe --json status     # after a failure
{"error":"..."}
```

`expires_at` and `remaining_seconds` are null for a hold with no time limit.
Timestamps are RFC 3339 in UTC.

## MCP

`maccafe mcp` serves three tools over stdio: `caffeine_on`, `caffeine_off`, and
`caffeine_status`. They return the same JSON the `--json` flag prints. The hold
runs in its own process, so it outlives the client disconnecting.

```
claude mcp add maccafe -- maccafe mcp
```

## State

`~/Library/Application Support/maccafe/` holds `state.json` and `lock`. The
holder keeps an exclusive `flock` on `lock` for its whole life, so a recycled
PID can never make `status` report a hold that no longer exists. If the holder
is killed, the kernel releases the assertion and the next `maccafe on` or
`maccafe off` clears the leftover `state.json`.

## License

MIT. See [LICENSE](LICENSE).
