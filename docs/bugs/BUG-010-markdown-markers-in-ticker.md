# BUG-010 — Markdown markers appeared literally in the ticker

## Symptom

The compact ticker could display text such as `**Implementing markdown stripping**`
instead of the readable plain-text summary.

## Root cause

The Markdown parser handles complete inline spans, but transcript text can be
captured while markup is incomplete or in a form the parser preserves. The
ticker has no attributed-text renderer, so preserved delimiters became visible.

## Fix

- Keep Foundation's Markdown-to-text conversion as the primary path.
- Apply a narrowly scoped plain-text fallback for strong emphasis, inline code,
  links, and headings.
- Normalize whitespace only after both stages.
- Cover each supported form in the ticker self-test.

## Verification

`./.build/thinkpeek --ticker-selftest` asserts the ticker output contains readable text
without Markdown delimiters and remains one line with valid vertical bounds.
