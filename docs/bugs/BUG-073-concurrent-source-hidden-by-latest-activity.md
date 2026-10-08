# BUG-073: Concurrent source hidden by latest activity

Status: Fixed

## Reproduction evidence

One Claude session was visibly running while ThoughtCop showed only a different
Codex session as `Working…`. The Claude JSONL still contained live tool records,
and the privacy audit confirmed that ThoughtCop consumed them. Later Codex
activity changed the single ticker source.

## Root cause

The operation state retained every active session, but the ticker rendered only
`latestActivitySource`. Any subsequent record from another session therefore hid
all other active sessions even though `/ui.activeSources` still contained them.

## Fix boundary

Single-session activity still displays its exact source. Concurrent activity now
uses an aggregate provider/count header and a scrolling status containing the
exact title and phase of every working or waiting session.

No reasoning is invented: the affected Claude `thinking` records had empty
plaintext fields, so the UI reports activity until the provider writes readable
reasoning.

## Verification

Presentation self-tests cover two providers and mixed working/waiting phases.
The isolated multi-session test requires both exact session names in the ticker
and checks the same values through `/ui`.
