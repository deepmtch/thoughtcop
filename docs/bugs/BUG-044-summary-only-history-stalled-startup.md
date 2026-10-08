# BUG-044: Summary-only history stalled startup

## Symptom

After summary text stopped masquerading as original reasoning, Doublethink could
remain unavailable during launch while consuming CPU on a large Codex rollout.
The local UI API never reached `initialScanComplete=true`.

## Cause

Historical backfill counted only unsealed plaintext blocks toward its requested
record limit. A Codex transcript containing only summaries and encrypted
reasoning therefore made the backwards reader scan the entire file looking for
plaintext that was not present. The HUD then discarded the same sealed records,
leaving an empty interface.

## Fix

- Count unavailable reasoning records as bounded history entries.
- Present their explicit unavailable state instead of filtering them out.
- Remove the obsolete `DOUBLETHINK_SHOW_ENCRYPTED` switch; it could not reveal or
  decrypt the original reasoning.
- Make the base transcript self-test use a deterministic local fixture instead
  of whichever large transcript happened to be newest.

## Verification

The complete test suite passes. A freshly launched production build completed
its initial scan and passed `Scripts/test_ui_api.py`. A metadata-only `/ui`
assertion reported two unavailable records, one plaintext analysis record, and
no occurrence of the known provider-summary phrase.
