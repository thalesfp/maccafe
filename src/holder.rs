use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

use anyhow::{Context, Result, bail};

use crate::assertion::Assertion;
use crate::lock;
use crate::state::{self, AssertionKind, Paths, State};

pub enum Until {
    Signal,
    Elapsed(Duration),
    CommandExit(Vec<String>),
}

impl Until {
    pub fn for_request(command: Vec<String>, limit: Option<Duration>) -> Self {
        if !command.is_empty() {
            Self::CommandExit(command)
        } else if let Some(limit) = limit {
            Self::Elapsed(limit)
        } else {
            Self::Signal
        }
    }
}

pub fn hold(paths: &Paths, kind: AssertionKind, until: Until) -> Result<i32> {
    let Some(_lock) = lock::acquire(&paths.lock_file())? else {
        let owner = state::read(paths)?
            .map(|state| format!(" (pid {})", state.pid))
            .unwrap_or_default();

        bail!("maccafe is already keeping this Mac awake{owner}; run `maccafe off` first");
    };

    let _assertion = Assertion::create(kind)?;

    let started_at = state::now();
    state::write(
        paths,
        &State {
            pid: std::process::id(),
            kind,
            started_at,
            expires_at: match &until {
                Until::Elapsed(limit) => Some(started_at + limit.as_secs()),
                _ => None,
            },
        },
    )?;

    let code = wait(until);

    state::remove(paths)?;

    code
}

fn wait(until: Until) -> Result<i32> {
    match until {
        Until::Signal => loop {
            std::thread::park();
        },
        Until::Elapsed(limit) => {
            sleep(limit);
            Ok(0)
        }
        Until::CommandExit(argv) => run_command(argv),
    }
}

fn run_command(argv: Vec<String>) -> Result<i32> {
    let (program, arguments) = argv.split_first().context("no command was given")?;

    let status = Command::new(program)
        .args(arguments)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("cannot run {program}"))?;

    Ok(exit_code(status))
}

fn exit_code(status: std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;

    status
        .code()
        .or_else(|| status.signal().map(|signal| 128 + signal))
        .unwrap_or(1)
}
