#!/usr/bin/env python3
"""Run a command under a controlled terminal situation and capture the streams apart.

The whole progress kit turns on which stream a byte lands on, so a harness that
cannot separate them cannot see the property. Under a pty, /dev/tty and a
forwarded stdout are the same stream: a combined capture cannot tell an
animation drawn on /dev/tty from one wrongly drawn to stdout. So the child gets
fd 1 and fd 2 on real files while its controlling terminal stays the pty, and
what comes back off the master is the /dev/tty stream and nothing else.

Modes, and the measurement behind each:

  (default)   pty with a controlling terminal. fd 0 comes from /dev/null, not
              from the pty: run_once_before_install-prerequisites.sh.tmpl:111
              reads a reply gated on `[ -t 0 ]`, and pty.fork() hands the child
              the pty, so the run sits at "Install them now? [Y/n]" forever.
  --setsid    no controlling terminal at all, so /dev/tty fails to open. This is
              the degradation contract's venue: ssh without a tty, a cron job.
              A captured apply is deliberately NOT this venue—its /dev/tty
              stays open, which is why a capture discriminates detectors instead.
  --cols N    pty winsize. Live lines are judged for wrapping at 40 columns, and
              only `stty size </dev/tty` can answer there: no script under
              `chezmoi apply` has COLUMNS set or TERM exported.

Every run is bounded. This tree has two ways to hang for an hour: an unanswered
prompt at install-prerequisites:111, and a spin_until at :99 waiting on Command
Line Tools that no harness can install. A run that hits the bound exits 199,
which is loud and never mistakable for a command's own status.
"""

import argparse
import errno
import fcntl
import os
import pty
import selectors
import signal
import struct
import sys
import termios

EXIT_TIMEOUT = 199  # distinct and loud: never mistakable for a command's own status
CTTY_KEEPALIVE_FD = 20  # high enough that no shell under test reaches for it


def set_winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stdout", required=True, help="file to receive the child's fd 1")
    ap.add_argument("--stderr", required=True, help="file to receive the child's fd 2")
    ap.add_argument("--tty-capture", help="file to receive the pty master stream")
    ap.add_argument("--setsid", action="store_true", help="no controlling terminal")
    ap.add_argument("--cols", type=int, default=80)
    ap.add_argument("--rows", type=int, default=24)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--cwd")
    ap.add_argument(
        "--glyphs",
        default="",
        help="frame glyphs to count in the master stream, as one string",
    )
    ap.add_argument(
        "--close-master-after-glyphs",
        type=int,
        default=0,
        help="close the pty master once this many frame glyphs have appeared, "
        "making /dev/tty present-but-unwritable",
    )
    ap.add_argument(
        "--sigint-after-glyphs",
        type=int,
        default=0,
        help="SIGINT the child's process group once this many frame glyphs have "
        "appeared; anchor the signal on an event, never on a wall clock",
    )
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    argv = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
    if not argv:
        sys.stderr.write("pty-run: no command given\n")
        return 2

    if args.setsid:
        return run_setsid(args, argv)
    return run_pty(args, argv)


def child_exec(args, argv):
    """Common child-side setup: fd 0 from /dev/null, fd 1 and fd 2 to real files."""
    devnull = os.open(os.devnull, os.O_RDONLY)
    os.dup2(devnull, 0)
    out = os.open(args.stdout, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    err = os.open(args.stderr, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    os.dup2(out, 1)
    os.dup2(err, 2)
    for fd in (devnull, out, err):
        if fd > 2:
            os.close(fd)
    if args.cwd:
        os.chdir(args.cwd)
    os.execvp(argv[0], argv)


def run_setsid(args, argv):
    pid = os.fork()
    if pid == 0:
        os.setsid()  # the form the constitution measured; drops the controlling terminal
        try:
            child_exec(args, argv)
        except Exception as exc:  # pragma: no cover - exec failure path
            sys.stderr.write("pty-run: exec failed: %s\n" % exc)
            os._exit(127)
    return reap(pid, args.timeout)


def run_pty(args, argv):
    master, slave = pty.openpty()
    set_winsize(slave, args.rows, args.cols)

    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)  # this pty becomes /dev/tty
        # Park the slave on a high fd and leave it open for the child's whole
        # life. On BSD the last close of a controlling terminal revokes it, so
        # a child that closes its slave finds /dev/tty answering
        # "Device not configured"—the venue this mode exists to rule out.
        # fd 1 and 2 still go to real files below, which is the separation the
        # measurement needs; an extra fd nobody reads changes nothing else.
        os.dup2(slave, CTTY_KEEPALIVE_FD)
        if slave != CTTY_KEEPALIVE_FD:
            os.close(slave)
        try:
            child_exec(args, argv)
        except Exception as exc:  # pragma: no cover - exec failure path
            sys.stderr.write("pty-run: exec failed: %s\n" % exc)
            os._exit(127)

    os.close(slave)
    return pump(master, pid, args)


def count_glyphs(buf, glyphs):
    """How many frame glyphs the master stream has carried so far.

    Counted over the accumulated buffer rather than per chunk, because a
    multi-byte glyph can straddle a read boundary and a per-chunk count would
    lose it exactly when the animation is fastest.
    """
    return sum(buf.count(g.encode("utf-8")) for g in glyphs)


def pump(master, pid, args):
    """Drain the master into --tty-capture until the child exits or time runs out.

    Two triggers can fire off this stream, and both are anchored on frames
    rather than on a wall clock. Timing by clock forks the result: a
    conforming kit measured red at 0.2s (a zero-byte capture from a run that
    had not started) and green at 2.0s (a capture identical to an
    uninterrupted run). The event is the only stable anchor.
    """
    sink = open(args.tty_capture, "wb", buffering=0) if args.tty_capture else None
    seen = bytearray()
    glyphs = list(args.glyphs)
    fired_close = False
    fired_sigint = False
    sel = selectors.DefaultSelector()
    sel.register(master, selectors.EVENT_READ)
    deadline = monotonic_deadline(args.timeout)
    status = None

    try:
        while True:
            remaining = deadline - now()
            if remaining <= 0:
                kill(pid)
                sys.stderr.write("pty-run: TIMEOUT after %.1fs\n" % args.timeout)
                return EXIT_TIMEOUT
            for _key, _mask in sel.select(timeout=min(remaining, 0.2)):
                try:
                    chunk = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno in (errno.EIO, errno.EBADF):
                        chunk = b""
                    else:
                        raise
                if not chunk:
                    sel.unregister(master)
                    break
                if sink:
                    sink.write(chunk)
                if glyphs:
                    seen.extend(chunk)
                    n = count_glyphs(seen, glyphs)
                    if (
                        args.sigint_after_glyphs
                        and not fired_sigint
                        and n >= args.sigint_after_glyphs
                    ):
                        fired_sigint = True
                        try:
                            os.killpg(os.getpgid(pid), signal.SIGINT)
                        except OSError:
                            pass
                    if (
                        args.close_master_after_glyphs
                        and not fired_close
                        and n >= args.close_master_after_glyphs
                    ):
                        fired_close = True
                        # Closing the master is the only way to make /dev/tty
                        # present-but-unwritable. It SIGHUPs the whole
                        # foreground group, so the script under test has to
                        # carry `trap "" HUP` or it dies at 129 before it can
                        # spill anything.
                        sel.unregister(master)
                        os.close(master)
                        master = -1
                        break
            if master == -1:
                status = reap(pid, max(deadline - now(), 0.1))
                return status
            if status is None:
                done, code = try_reap(pid)
                if done:
                    status = code
                    # One more non-blocking drain: the child's last frames may
                    # still be sitting in the pty buffer after it exits.
                    drain(master, sink)
                    return status
    finally:
        if sink:
            sink.close()
        if master != -1:
            try:
                os.close(master)
            except OSError:
                pass


def drain(master, sink):
    fl = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    while True:
        try:
            chunk = os.read(master, 65536)
        except (OSError, BlockingIOError):
            return
        if not chunk:
            return
        if sink:
            sink.write(chunk)


def try_reap(pid):
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == 0:
        return False, None
    return True, exit_code(status)


def reap(pid, timeout):
    deadline = monotonic_deadline(timeout)
    while now() < deadline:
        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid != 0:
            return exit_code(status)
        sleep(0.02)
    kill(pid)
    sys.stderr.write("pty-run: TIMEOUT after %.1fs\n" % timeout)
    return EXIT_TIMEOUT


def exit_code(status):
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return os.WEXITSTATUS(status)


def kill(pid):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(pid), sig)
        except OSError:
            try:
                os.kill(pid, sig)
            except OSError:
                return
        sleep(0.1)
        try:
            if os.waitpid(pid, os.WNOHANG)[0] != 0:
                return
        except OSError:
            return


def now():
    import time

    return time.monotonic()


def monotonic_deadline(timeout):
    return now() + timeout


def sleep(seconds):
    import time

    time.sleep(seconds)


if __name__ == "__main__":
    sys.exit(main())
