import Darwin
import Foundation

// Try to acquire an exclusive flock on `path`. On success returns the
// file descriptor (kept open for the remaining process lifetime so the
// lock stays held until exit). On failure returns -1 — another killwindow
// instance is already running.
//
// The fd is intentionally not closed when this function returns: POSIX
// advisory locks are tied to the fd, so closing would release the lock.
// Leaving it open costs one fd and is reclaimed automatically on exit.
func tryAcquireLock(at path: String) -> Int32 {
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    if fd < 0 { return -1 }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return -1
    }
    return fd
}

let clickLockPath  = "/tmp/killwindow.click.lock"
let daemonLockPath = "/tmp/killwindow.daemon.lock"
