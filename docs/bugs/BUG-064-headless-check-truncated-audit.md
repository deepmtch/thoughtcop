# BUG-064 — Headless check truncated the live privacy audit

## User-visible failure

Running `thoughtcop --check` to verify the configured checker erased the existing
privacy audit before recording the one-shot request and result.

## Evidence and cause

The command path called `PrivacyAudit.start()` with its default `reset: true`.
That is appropriate for a newly launched UI run, but destructive for a
diagnostic command while the UI process is still active.

## Fix

The headless check now opens the audit with `reset: false`. The audit helper
creates the file when it does not exist and otherwise appends. The UI launch
continues to start a fresh run exactly as before.

The privacy-audit self-test starts an audit twice, with the second start in
append mode, and verifies that both start records remain.
