# BUG-033 — Open reader followed new messages

## Symptom

While the full-message reader was open, newly arriving events could advance the
selected index and replace the message being read. Evaluator completion could
also rewrite the displayed text asynchronously.

## Root cause

The compact selection automatically followed the newest event whenever it had
been at the end of history. Reader mode reused that live selection and repeatedly
rendered it instead of owning a stable reading snapshot.

## Fix

- Capture source, rendered text, and kind when the reader opens.
- Never advance compact selection for new events while reader mode is active.
- Never rewrite the open reader for evaluator completion or feed relayout.
- On Done, Escape, outside-close, or leaving the reader for controls, select the
  newest event and resume the ticker.

## Source-data boundary

For the reported `Identifying overstrict grading criteria` event, the local Codex
transcript contains only that readable one-line summary. Its paired reasoning
record contains encrypted content, which Doublethink cannot decrypt. No readable
body was discarded, and Doublethink does not manufacture hidden reasoning.

## Verification

The reader-freeze regression simulates two new events while reading the latest
message, confirms the selected index and snapshot remain unchanged, and confirms
closing resolves to the newest index.
