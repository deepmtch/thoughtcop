# BUG-042: Codex summary Markdown made every line bold

## Symptom

A multi-entry Codex reasoning item appeared as a vertical stack of bold headings
instead of readable body text.

## Evidence

The selected `2026-08-15T17:22:10.707Z` transcript record contains exactly three
`summary_text` entries, and all three values are wrapped in `**…**`. ThoughtCop
preserved and displayed all three entries; the defect was presentation, not
missing transcript content. A later `17:22:24.925Z` record contains four entries
and remains a separate reasoning item.

## Cause

The shared analysis renderer honored Codex's strong-emphasis Markdown on every
summary entry. Because Codex uses that markup systematically, an entire reasoning
card was rendered bold.

## Fix

Analysis summaries keep their complete parsed text and paragraph boundaries but
use ThoughtCop's regular reasoning-body font. This is an explicit policy for the
`analysis` event kind, not a content-dependent heuristic. Other presentation
kinds retain their existing font policy.

## Verification

`--two-summary-card-selftest` now checks all summary text is present, spans
multiple rendered paragraphs, and uses a non-bold font.
