use std::fmt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

use anyhow::{Context, Result, bail};

use crate::lock;
use crate::state::{self, AssertionKind, Paths, State};

const HOLDER_HANDSHAKE: Duration = Duration::from_secs(3);
const FIRST_POLL: Duration = Duration::from_millis(2);
const SLOWEST_POLL: Duration = Duration::from_millis(25);

#[derive(Debug, PartialEq, Eq)]
pub enum OffAction {
    NothingToDo,
    ClearStale,
    Stop { pid: u32 },
}

pub fn decide_off(state: Option<&State>, holder_is_alive: bool) -> OffAction {
    match (state, holder_is_alive) {
        (Some(state), true) => OffAction::Stop { pid: state.pid },
        (Some(_), false) => OffAction::ClearStale,
        (None, _) => OffAction::NothingToDo,
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum StatusReport {
    Off,
    On {
        pid: u32,
        kind: AssertionKind,
        elapsed: Duration,
        remaining: Option<Duration>,
    },
}

pub fn render_status(state: Option<&State>, holder_is_alive: bool, now: u64) -> StatusReport {
    let Some(state) = state else {
        return StatusReport::Off;
    };

    if !holder_is_alive {
        return StatusReport::Off;
    }

    StatusReport::On {
        pid: state.pid,
        kind: state.kind,
        elapsed: Duration::from_secs(now.saturating_sub(state.started_at)),
        remaining: state
            .expires_at
            .map(|expiry| Duration::from_secs(expiry.saturating_sub(now))),
    }
}

impl fmt::Display for OffAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Stop { .. } => write!(f, "{}", StatusReport::Off),
            Self::ClearStale | Self::NothingToDo => {
                write!(f, "off: this Mac was already free to sleep")
            }
        }
    }
}

impl fmt::Display for StatusReport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Off => write!(f, "off: this Mac can sleep normally"),
            Self::On {
                pid,
                kind,
                elapsed,
                remaining,
            } => {
                write!(
                    f,
                    "on: preventing {} for {} (pid {pid})",
                    kind.label(),
                    crate::duration::format(*elapsed)
                )?;

                match remaining {
                    Some(left) => write!(f, ", {} left", crate::duration::format(*left)),
                    None => write!(f, ", no time limit"),
                }
            }
        }
    }
}

fn read_hold(paths: &Paths) -> Result<(Option<State>, bool)> {
    let state = state::read(paths)?;
    let alive = lock::holder_is_alive(&lock::open(&paths.lock_file())?)?;

    Ok((state, alive))
}

pub fn read_status(paths: &Paths) -> Result<StatusReport> {
    let (state, alive) = read_hold(paths)?;

    Ok(render_status(state.as_ref(), alive, state::now()))
}

pub fn turn_off(paths: &Paths) -> Result<OffAction> {
    let (state, alive) = read_hold(paths)?;
    let action = decide_off(state.as_ref(), alive);

    match action {
        OffAction::NothingToDo => {}
        OffAction::ClearStale => state::remove(paths)?,
        OffAction::Stop { pid } => {
            stop_holder(pid, &paths.lock_file())?;
            state::remove(paths)?;
        }
    }

    Ok(action)
}

fn stop_holder(pid: u32, lock_file: &Path) -> Result<()> {
    let signalled = unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM) };

    if signalled != 0 {
        let err = std::io::Error::last_os_error();
        if err.raw_os_error() != Some(libc::ESRCH) {
            return Err(err).with_context(|| format!("cannot stop the holder process {pid}"));
        }
    }

    let file = lock::open(lock_file)?;
    let stopped = poll_for(HOLDER_HANDSHAKE, || {
        Ok((!lock::holder_is_alive(&file)?).then_some(()))
    })?;

    if stopped.is_some() {
        return Ok(());
    }

    bail!("the holder process {pid} did not stop")
}

pub fn turn_on(
    paths: &Paths,
    kind: AssertionKind,
    limit: Option<Duration>,
) -> Result<StatusReport> {
    turn_off(paths)?;

    let executable = std::env::current_exe().context("cannot find the maccafe executable")?;

    let mut child = Command::new(executable)
        .args(crate::cli::hold_arguments(kind, limit))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .context("cannot start the maccafe holder process")?;

    let pid = child.id();

    let started = poll_for(HOLDER_HANDSHAKE, || {
        if let Some(status) = child.try_wait()? {
            bail!("{}", holder_failure(&mut child, status));
        }

        Ok(state::read(paths)?.filter(|state| state.pid == pid))
    })?;

    let Some(state) = started else {
        let _ = child.kill();
        bail!("the holder process did not report back in time");
    };

    Ok(render_status(Some(&state), true, state::now()))
}

fn holder_failure(child: &mut std::process::Child, status: std::process::ExitStatus) -> String {
    use std::io::Read;

    let mut message = String::new();
    if let Some(stderr) = child.stderr.as_mut() {
        let _ = stderr.read_to_string(&mut message);
    }

    let message = message.trim();
    if message.is_empty() {
        format!("the holder process exited with {status}")
    } else {
        message.to_string()
    }
}

fn poll_for<T>(limit: Duration, mut ready: impl FnMut() -> Result<Option<T>>) -> Result<Option<T>> {
    let deadline = std::time::Instant::now() + limit;
    let mut pause = FIRST_POLL;

    loop {
        if let Some(value) = ready()? {
            return Ok(Some(value));
        }

        if std::time::Instant::now() >= deadline {
            return Ok(None);
        }

        sleep(pause);
        pause = (pause * 2).min(SLOWEST_POLL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a_state() -> State {
        State {
            pid: 321,
            kind: AssertionKind::Display,
            started_at: 1_000,
            expires_at: Some(1_600),
        }
    }

    #[test]
    fn stops_the_holder_that_is_still_running() {
        assert_eq!(
            decide_off(Some(&a_state()), true),
            OffAction::Stop { pid: 321 }
        );
    }

    #[test]
    fn clears_state_left_behind_by_a_killed_holder() {
        assert_eq!(decide_off(Some(&a_state()), false), OffAction::ClearStale);
    }

    #[test]
    fn does_nothing_when_the_mac_is_already_free_to_sleep() {
        assert_eq!(decide_off(None, false), OffAction::NothingToDo);
    }

    #[test]
    fn reports_elapsed_and_remaining_time_for_a_live_hold() {
        let report = render_status(Some(&a_state()), true, 1_240);

        assert_eq!(
            report,
            StatusReport::On {
                pid: 321,
                kind: AssertionKind::Display,
                elapsed: Duration::from_secs(240),
                remaining: Some(Duration::from_secs(360)),
            }
        );
    }

    #[test]
    fn reports_no_time_limit_for_an_open_ended_hold() {
        let state = State {
            expires_at: None,
            ..a_state()
        };

        let report = render_status(Some(&state), true, 1_240);

        assert!(matches!(
            report,
            StatusReport::On {
                remaining: None,
                ..
            }
        ));
    }

    #[test]
    fn reports_off_when_the_recorded_holder_is_gone() {
        assert_eq!(
            render_status(Some(&a_state()), false, 1_240),
            StatusReport::Off
        );
    }

    #[test]
    fn reports_off_when_nothing_was_ever_recorded() {
        assert_eq!(render_status(None, true, 1_240), StatusReport::Off);
    }
}
