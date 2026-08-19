use std::fs::{File, OpenOptions};
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

fn take(file: &File) -> Result<bool> {
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
