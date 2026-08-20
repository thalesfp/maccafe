use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum AssertionKind {
    Display,
    System,
}

impl AssertionKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Display => "display and system sleep",
            Self::System => "system sleep",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct State {
    pub pid: u32,
    pub kind: AssertionKind,
    pub started_at: u64,
    pub expires_at: Option<u64>,
}

pub struct Paths {
    pub dir: PathBuf,
}

impl Paths {
    pub fn state_file(&self) -> PathBuf {
        self.dir.join("state.json")
    }

    pub fn lock_file(&self) -> PathBuf {
        self.dir.join("lock")
    }
}

pub fn paths() -> Result<Paths> {
    let home = std::env::var_os("HOME").context("HOME is not set")?;
    let dir = Path::new(&home)
        .join("Library")
        .join("Application Support")
        .join("maccafe");

    fs::create_dir_all(&dir).with_context(|| format!("cannot create {}", dir.display()))?;

    Ok(Paths { dir })
}

pub fn read(paths: &Paths) -> Result<Option<State>> {
    let file = paths.state_file();

    let raw = match fs::read_to_string(&file) {
        Ok(raw) => raw,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(err) => return Err(err).with_context(|| format!("cannot read {}", file.display())),
    };

    serde_json::from_str(&raw)
        .map(Some)
        .with_context(|| format!("cannot read the hold recorded in {}", file.display()))
}

pub fn write(paths: &Paths, state: &State) -> Result<()> {
    let file = paths.state_file();
    let temp = paths.dir.join("state.json.tmp");

    let body = serde_json::to_string_pretty(state)?;
    fs::write(&temp, body).with_context(|| format!("cannot write {}", temp.display()))?;
    fs::rename(&temp, &file).with_context(|| format!("cannot replace {}", file.display()))?;

    Ok(())
}

pub fn remove(paths: &Paths) -> Result<()> {
    match fs::remove_file(paths.state_file()) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err.into()),
    }
}

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn survives_a_write_and_read_round_trip() {
        let state = State {
            pid: 4242,
            kind: AssertionKind::Display,
            started_at: 1_700_000_000,
            expires_at: Some(1_700_003_600),
        };

        let encoded = serde_json::to_string(&state).unwrap();
        let decoded: State = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded, state);
    }

    #[test]
    fn keeps_an_open_ended_hold_without_an_expiry() {
        let state = State {
            pid: 1,
            kind: AssertionKind::System,
            started_at: 10,
            expires_at: None,
        };

        let encoded = serde_json::to_string(&state).unwrap();

        assert!(encoded.contains("\"expires_at\":null"));
        assert_eq!(serde_json::from_str::<State>(&encoded).unwrap(), state);
    }
}
