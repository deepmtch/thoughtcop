# BUG-067: stale working state and blocking manual restart

Status: fixed

## Observed behavior

The ticker could remain on `Claude + Codex · working…` after a provider turn had
ended. Running `./restart.sh` also kept the invoking terminal occupied, which
looked like a hung restart while the GUI process was running.

## Root cause

- The transcript parser converted any unknown JSONL record into an activity
  update. Metadata and snapshots could therefore create or extend a working
  state without a matching completion.
- Claude emits an explicit `system/turn_duration` record after a turn whose last
  assistant record may be a tool call. That terminal record was ignored.
- Codex `turn_aborted` was not treated as a terminal lifecycle record.
- A session's generated title could appear between its start and finish records.
  Activity was keyed by that mutable display title, so the finish record could
  not clear the title-less start record.
- `restart.sh` used `exec` to replace the shell with the GUI executable instead
  of asking LaunchServices to own the process.

## Fix

- Only explicit provider and lifecycle records may mutate activity state.
- Map Claude `turn_duration` and Codex `turn_aborted` to `finished`.
- Key activity by immutable provider/session ID while allowing its display title
  to update independently.
- Launch the rebuilt app bundle through LaunchServices and return to the shell.

No timeout or content heuristic is used.

## Verification

- Parser self-tests assert both terminal records clear activity.
- An unrelated metadata record produces no activity block.
- The multi-session end-to-end test still verifies concurrent Claude and Codex
  activity, exact reasoning payloads, checker results, and final inactive state.
