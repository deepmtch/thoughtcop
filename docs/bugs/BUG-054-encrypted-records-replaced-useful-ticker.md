# BUG-054 — Encrypted records replaced useful ticker content

## User-visible failure

Every Codex encrypted reasoning record became a navigable UI item saying that
original reasoning was unavailable. Because encrypted records are frequent,
that placeholder repeatedly replaced useful plaintext reasoning in the ticker
while work continued.

## Cause

The transcript parser correctly marked encrypted records as not externally
evaluable, but still emitted a sealed presentation block. The HUD treated that
block as the newest message before skipping checker evaluation.

## Fix

Encrypted reasoning, summary-only reasoning, and empty Claude thinking records
now remain audit-only. The parser emits no presentation block for them, so they
cannot enter cards, navigation, the local UI API event list, or the ticker.
Plaintext `thinking` and `reasoning_text` records are unchanged.

## Verification

Provider-boundary tests require encrypted and summary-only fixtures to produce
zero UI blocks while complete Claude and Codex plaintext reasoning remains
presentable and externally evaluable.
