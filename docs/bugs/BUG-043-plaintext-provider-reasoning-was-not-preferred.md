# BUG-043: Plaintext provider reasoning was not preferred

## Symptom

The provider contract permits an OpenAI reasoning item to contain both
`content[].reasoning_text` and `summary[]`, but Thinkpeek always displayed the
summary array. Claude's separate `message.content[].thinking` path already
preserved the complete plaintext field.

## Cause

The Codex parser implemented only summary and encrypted-only branches. It had no
explicit branch for plaintext `reasoning_text` content.

## Fix

- Display every nonempty `reasoning_text` entry, in order, when present.
- Fall back to every nonempty `summary_text` entry only when plaintext reasoning
  content is absent.
- Keep complete plaintext local. The external checker receives the provider's
  summary, not the longer display text. If the provider supplies no summary, the
  item is displayed locally and is not externally evaluated.
- Continue displaying the complete Claude `thinking` string unchanged.

These are explicit schema branches. No content-dependent heuristic is used.

## Verification

`--provider-reasoning-selftest` checks OpenAI plaintext priority, OpenAI summary
fallback, local-only handling without a summary, and exact multi-paragraph Claude
thinking preservation.

An isolated build of pre-change commit `a9b79e8` was also run against the current
local transcripts. Its Codex self-test displayed the same single short
`agent_reasoning` phrase, proving the previous parser did not decrypt or expose a
longer Codex field.
