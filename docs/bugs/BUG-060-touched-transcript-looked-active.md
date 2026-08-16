# BUG-060 — Touched old transcript looked like the active conversation

## User-visible failure

The ticker could remain on an old Claude conversation while current Codex tasks
were running. In the reproduced state, it showed `Claude · JSU TGO THERE` from
August 15 after that transcript file was touched again on August 16.

## Evidence and cause

The transcript's last timestamped conversation record was
`2026-08-15T21:00:57.340Z`, but its filesystem modification time was refreshed
on August 16. Discovery treated modification time as conversation activity and
backfilled the old reasoning into the ticker.

Current Codex records were also inspected. They contained `summary_text` plus
encrypted content but no plaintext `reasoning_text`; under the configured
reasoning-only boundary they were intentionally not ticker items.

## Fix

Discovery now reads backward to the last timestamped transcript record and uses
that exact event time as activity time. A file with no timestamped record yet
(including a new empty transcript) temporarily uses filesystem modification
time until its first timestamped record arrives.

The privacy audit now distinguishes `provider_summary_not_sent` from
`reasoning_selected`, so logs no longer imply a summary-only Codex record was
eligible for display or external checking.

## Verification

The source-context self-test creates an old timestamped transcript followed by
untimestamped metadata and verifies that activity remains the old record time.
The privacy-audit self-test separately covers plaintext reasoning, provider-only
summaries, tools, outbound requests, and content-free logging.
