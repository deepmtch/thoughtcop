# BUG-062 — Claude question remained stuck in working state

## User-visible failure

After Claude displayed an interactive question and waited for the user,
Doublethink continued to label that Claude session `working…`. It could remain
stuck indefinitely because the cloud turn did not emit a normal `result` event.

## Evidence and cause

The captured Claude cloud SSE sequence ended with `control_request` for
`AskUserQuestion`, trailing `stream_event` frames, and `task_summary`. There was
no `result` event. Doublethink recognized only `requesting`, `stream_event`, and
`result`, so the last recognized state was still active.

## Fix

Provider activity now has an explicit `waiting for you` state:

- Claude cloud `control_request` transitions that session from active to waiting;
- local Claude `AskUserQuestion` tool-use records make the same transition;
- trailing stream frames from the same turn cannot reactivate a waiting session;
- a later exact start event resumes work, while completion clears both states;
- the local UI API exposes active and waiting sessions separately.

No timer, text classifier, or title heuristic is used.

## Verification

The presentation self-test runs concurrent Claude and Codex activity, moves
only Claude to waiting, proves a trailing update cannot reactivate it, completes
Codex independently, and verifies the visible Claude waiting title. The cloud
parser fixture reproduces the exact `control_request` plus trailing-frame order.
