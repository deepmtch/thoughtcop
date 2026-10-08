# BUG-087 — Copied chat history was checked again

## Evidence

The user saw violations for very old messages. Of this Mac's 300 most recent
Claude Code transcripts on 2026-10-02, 33 begin with messages written 1 to 97
hours before the file was created (resumed chats and sub-agents copy earlier
messages into a new file). Doublethink tails a file created after launch from
byte zero, so every copied message was sent to the checker as if it were new.

## Root cause

Eligibility for checking was decided by file position (new bytes since launch),
not by when the record was written.

## Fix

Only records whose own provider timestamp is at or after the moment Doublethink
started are checked (`writtenSinceLaunch`). Older records are still displayed
but carry "Not checked · written before Doublethink started"; a record without a
readable timestamp is not checked and says so (`drift-skipped-old` with a
reason in `/ui`). Saved violations are unaffected.

## Verification

- `--evaluator-selftest`: before/after launch, millisecond, microsecond and
  offset timestamps, unreadable values.
- `Scripts/test_violation_verification_e2e.py`: a resumed-chat file starting
  with a message stamped 2026-09-28 followed by a new one; the old copy is never
  sent, the new one is checked.
