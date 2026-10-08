# BUG-049: post-commit launch jobs created a relaunch loop

## User-visible failure

Thoughtcrime repeatedly disappeared, returned in its empty startup state, and then
disappeared again without any new commit.

## Evidence and root cause

The local app log contained thirteen consecutive `replaced 1 running instance`
records. `launchctl list` showed two separately labelled post-commit jobs. Each
job was treated as restartable: the newer Thoughtcrime process terminated the older
one through `SingleInstance`, launchd restarted the terminated job, and the two
jobs continuously replaced each other.

## Fix

- Remove both installed one-off launch jobs.
- Package the binary as a minimal macOS app bundle during the normal build.
- Keep the successful-build gate, then open that bundle once through
  LaunchServices instead of registering a restartable service.
- Verify the new process remains alive before the hook returns.

## Verification

The hook test checks that one process remains, no
`com.thoughtcrime.postcommit.*` launch jobs exist, and the replacement app answers
its local UI API without producing additional replacement records.
