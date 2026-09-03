# BUG-070: Codex double-UUID rollout used the wrong task title

Status: Fixed

## Reproduction evidence

The active rollout filename contained two UUIDs:

`...-01a02dd4-2314-7f30-8313-b23268b2c1ae_01a02dee-e313-7d60-8222-ff6e9c8c5c6b.jsonl`

Its first `session_meta` record identified the owning session as
`01a02dd4-2314-7f30-8313-b23268b2c1ae`, and `session_index.jsonl` mapped that ID
to the user-visible task title `imrpove process`. Thinkpeek instead displayed
`task 01a02dee`.

## Root cause

`codexSessionID(from:)` unconditionally took the final 36 filename characters.
That happened to work for ordinary rollout filenames but selected the second,
non-owning UUID from this rollout.

## Fix boundary

Codex identity now comes from the authoritative first
`session_meta.payload.id` record. The filename suffix remains a compatibility
fallback for old or incomplete transcripts that do not contain that record.
Successfully parsed metadata IDs are cached so title refreshes do not repeatedly
read the transcript.

## Verification

The session-discovery self-test creates the observed double-UUID filename with a
first-record task ID and verifies that the metadata ID wins.
