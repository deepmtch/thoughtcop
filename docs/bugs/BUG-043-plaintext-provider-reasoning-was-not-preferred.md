# BUG-043: Plaintext provider reasoning was not preferred

## Symptom

The provider contract permits an OpenAI reasoning item to contain both
`content[].reasoning_text` and `summary[]`, but Thoughtcrime always displayed the
summary array. Claude's separate `message.content[].thinking` path already
preserved the complete plaintext field.

## Cause

The Codex parser implemented only summary and encrypted-only branches. It had no
explicit branch for plaintext `reasoning_text` content.

## Fix

- Display every nonempty `reasoning_text` entry, in order, when present.
- Never fall back to `summary_text`: it is provider-generated summary material,
  not the original reasoning requested by the user.
- When plaintext reasoning is absent, show an explicit unavailable state without
  displaying summary text as if it were original reasoning.
- Keep complete plaintext local and never send it to the external checker.
- Continue displaying the complete Claude `thinking` string unchanged.

These are explicit schema branches. No content-dependent heuristic is used.

## Verification

`--provider-reasoning-selftest` checks exact OpenAI plaintext preservation,
rejects summary fallback, verifies the unavailable state, and checks exact
multi-paragraph Claude thinking preservation.

An isolated build of pre-change commit `a9b79e8` was also run against the current
local transcripts. Its Codex self-test displayed the same single short
`agent_reasoning` phrase, proving the previous parser did not decrypt or expose a
longer Codex field.
