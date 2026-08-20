use std::ffi::CStr;
use std::path::Path;

/// The name of the running executable, or None if the pid owns no live process.
pub fn executable_name(pid: libc::pid_t) -> Option<String> {
    let mut buffer = [0u8; libc::PROC_PIDPATHINFO_MAXSIZE as usize];

    let written =
        unsafe { libc::proc_pidpath(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };

    if written <= 0 {
        return None;
    }

    let path = CStr::from_bytes_until_nul(&buffer).ok()?.to_str().ok()?;

    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
}

pub fn own_executable_name() -> Option<String> {
    std::env::current_exe()
        .ok()?
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
}
