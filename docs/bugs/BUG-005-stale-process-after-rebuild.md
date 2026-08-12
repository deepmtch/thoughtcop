# BUG-005: Rebuilt binary left the old process on screen

Status: fixed

## Observed behavior

After BUG-004 was committed and the executable rebuilt, the visible window still
showed `Claude operation started` as its card. The committed behavior appeared not
to work.

## Root cause

The visible process (PID 15097) had started at 10:12, before the fixed executable
was rebuilt at 11:53. Replacing a Mach-O file on disk does not modify code already
mapped into a running process. The source, tests, and disk binary were correct,
but the deployment handoff left the stale process running.

## Fix

- Replaced the stale process with the rebuilt executable.
- Added `restart.sh`, which builds first and then starts the new binary; the
  single-instance policy terminates the old process only after a successful build.
- Made `build.sh` warn when an existing Thinkpeek process still needs replacement.
- Documented the rebuild-and-replace command in the main usage block.

## Verification

The replacement process started at 11:55 as PID 95074. Its live `/ui` state
reported:

```text
operationPending: true
navigableCount: 3
peekText: Planning termination and relaunch of old processes
windowTitle: ● Codex · task 019ff546 · working…
```

The activity event did not appear in `events`, did not consume a history slot,
and did not replace the useful peek text. A live screenshot confirmed the useful
summary remained visible.
