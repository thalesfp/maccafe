# maccafe

A macOS CLI that keeps the Mac awake with an IOKit power assertion.

## Invariants

Rules that are not obvious from any single file. Break one and the tool lies
about whether the Mac is awake.

- **One holder at a time.** A hold is a separate process that owns an exclusive
  `flock` on `lock` and the IOKit assertion. `on` replaces an existing hold;
  `run` refuses to start while one exists.
- **The lock file names the process to signal.** The holder writes its pid into
  the lock file while holding the lock. `off` signals that pid and never the one
  in `state.json`, which any process can edit.
- **Lock occupancy decides, not the state file.** `off` stops whatever owns the
  lock even when `state.json` is missing or unreadable.
- **The kernel cleans up.** Both the `flock` and the assertion are released when
  the holder dies, so a `kill -9` leaks only a stale `state.json`, which the next
  `on` or `off` clears.
- **`PreventUserIdleDisplaySleep` is the default** because it also blocks idle
  system sleep. `--system-only` is the narrower assertion.
- **A hold outlives the client that asked for it.** The MCP tools start the same
  detached holder `on` does, never an assertion inside the server process, so the
  Mac stays awake after the client disconnects.
- **Nothing survives a closed lid**, low battery, or a requested sleep. That is
  the platform, not a bug.

## Modules

| File | Owns |
|---|---|
| `src/assertion.rs` | The IOKit FFI and an RAII guard that releases on drop |
| `src/lock.rs` | The `flock` mechanism and the recorded lock owner |
| `src/state.rs` | `state.json`, its paths, and `AssertionKind` |
| `src/process.rs` | Reading a pid's executable name through `proc_pidpath` |
| `src/holder.rs` | The process that takes the assertion and waits |
| `src/control.rs` | `on`/`off`/`status`, plus the pure decision functions |
| `src/duration.rs` | Parsing and formatting `45s`, `90m`, `1h30m` |
| `src/timestamp.rs` | Unix seconds to RFC 3339, no dependency |
| `src/report.rs` | The wire shape shared by `--json` and MCP |
| `src/mcp.rs` | The stdio MCP server: `caffeine_on`, `caffeine_off`, `caffeine_status` |
| `src/cli.rs` | The clap surface and the argv for the detached holder |
| `src/main.rs` | Dispatch only |

## Commands

```
make            # list every target
make verify     # format check, clippy with -D warnings, tests: the gate
make run ARGS="status"
make release
```

`cargo` is not on the default PATH on the author's machine; the Makefile finds it.

## Conventions

- Decision logic stays pure and takes values, not paths or handles, so it tests
  without spawning a process or touching IOKit. `decide_off`, `render_status`,
  `duration::parse`, and everything in `report.rs` follow this. Keep new logic
  on that side of the line.
- Tests are named for the behavior a caller relies on, not the function under
  test.
- Do not add a dependency without asking. RFC 3339 formatting is hand-written
  for exactly this reason.
- `--json` is a global flag. `cli::parse` rejects it for `run`, which streams
  the output of the command it holds for, so the combination fails as a clap
  usage error before any command runs, as it does for `mcp`. Both renderings live
  in `report.rs`, and `mcp.rs` calls the same `status_value`/`off_value`, so the
  CLI and the MCP tools cannot report different things.
- The reviewed decision on lock security: a process that can rewrite the lock
  file already runs as the user and can signal any of their processes directly,
  so `fcntl`/`F_GETLK` was considered and declined. Revisit only if maccafe ever
  crosses a privilege boundary.
