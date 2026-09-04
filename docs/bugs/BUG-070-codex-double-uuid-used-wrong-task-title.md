# BUG-070: Codex double-UUID rollout used the wrong task title

Status: Fixed

## Reproduction evidence

The active rollout filename contained two UUIDs:

`...-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa_bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jsonl`

Its first `session_meta` record identified the owning session as
`aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, and `session_index.jsonl` mapped that ID
to the synthetic task title `Primary task`. Thinkpeek instead displayed a short
form of the non-owning suffix UUID.

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

The session-discovery self-test creates a synthetic double-UUID filename with a
first-record task ID and verifies that the metadata ID wins.
