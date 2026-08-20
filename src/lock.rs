use std::fs::{File, OpenOptions};
use std::os::unix::fs::FileExt;
use std::os::unix::io::AsRawFd;
use std::path::Path;

use anyhow::{Context, Result};

pub fn open(path: &Path) -> Result<File> {
    OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(path)
        .with_context(|| format!("cannot open {}", path.display()))
}

/// Takes the lock and reports whether this process now holds it.
pub fn take(file: &File) -> Result<bool> {
    let taken = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };

    if taken == 0 {
        return Ok(true);
    }

    let err = std::io::Error::last_os_error();
    match err.raw_os_error() {
        Some(libc::EWOULDBLOCK) => Ok(false),
        _ => Err(err).context("cannot lock the maccafe state"),
    }
}

/// The returned file holds the lock; the kernel drops it when the file closes.
pub fn acquire(path: &Path) -> Result<Option<File>> {
    let file = open(path)?;

    if take(&file)? {
        Ok(Some(file))
    } else {
        Ok(None)
    }
}

pub fn holder_is_alive(file: &File) -> Result<bool> {
    Ok(!take(file)?)
}

/// Records which process owns the lock, so another process can identify the
/// holder without trusting a file anyone can edit.
pub fn claim(file: &File, pid: u32) -> Result<()> {
    file.set_len(0).context("cannot clear the maccafe lock")?;
    file.write_all_at(pid.to_string().as_bytes(), 0)
        .context("cannot record the maccafe lock owner")?;

    Ok(())
}

pub fn disown(file: &File) -> Result<()> {
    file.set_len(0).context("cannot clear the maccafe lock")
}

/// The pid the owner recorded, or None while it is still writing it.
pub fn owner(path: &Path) -> Result<Option<u32>> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(text.trim().parse().ok()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err).with_context(|| format!("cannot read {}", path.display())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a_lock_path(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!("maccafe-{}-{}.lock", name, std::process::id()))
    }

    #[test]
    fn refuses_a_second_holder_while_the_first_holds_the_lock() {
        let path = a_lock_path("busy");
        let first = acquire(&path).unwrap();

        let second = acquire(&path).unwrap();

        assert!(first.is_some());
        assert!(second.is_none());
    }

    #[test]
    fn frees_the_lock_when_the_holder_lets_it_go() {
        let path = a_lock_path("released");
        drop(acquire(&path).unwrap());

        let next = acquire(&path).unwrap();

        assert!(next.is_some());
    }

    #[test]
    fn tells_a_second_process_which_process_owns_the_lock() {
        let path = a_lock_path("owned");
        let held = acquire(&path).unwrap().unwrap();
        claim(&held, 4242).unwrap();

        let seen = owner(&path).unwrap();

        assert_eq!(seen, Some(4242));
    }

    #[test]
    fn names_no_owner_once_the_lock_is_given_up() {
        let path = a_lock_path("disowned");
        let held = acquire(&path).unwrap().unwrap();
        claim(&held, 4242).unwrap();

        disown(&held).unwrap();

        assert_eq!(owner(&path).unwrap(), None);
    }

    #[test]
    fn keeps_the_lock_the_caller_took_while_stopping_a_holder() {
        let path = a_lock_path("held");
        let held = open(&path).unwrap();
        assert!(take(&held).unwrap());

        let other = acquire(&path).unwrap();

        assert!(other.is_none());
    }
}
