# BUG-088 — Violation history was overloaded

## Evidence

User screenshot (2026-10-02): each violation was a large red card with a
badge, a 15 pt multi-line model explanation, the evidence, and a long
"Checked by Groq · model · confirmed by second check · ms" footer, in a
700 × 620 window.

## Fix (mockup option C, approved by the user)

- History window 380 points wide (was 700, minimum 520).
- A violation is a two-line row: red dot (new) or grey dot (reviewed), source
  and time, then the quoted evidence on one truncated line. No badge, red
  fill, border, or footer.
- Clicking a row (or `/toggle-selected-violation`) expands it in place: full
  quote, "Why:" reason clamped to two lines, check details and an
  "Open full message" link. Double-click, Return and Space open the reader.
- The hidden violation empty state is removed from the feed stack: its hidden
  width chain (390 + 42 + 42 + 36) held the history at 510 points.

## Review follow-up (parallel visual review in the Parallels VM)

- An expanded "Why:" stayed on one line: a truncating line-break mode disables
  wrapping. It now wraps to at most two lines.
- The empty state widened history to 510 points: its single-line explanation
  demanded its full width (390 + 2 × 42). It now wraps within the window.
- Expanded and selected rows looked alike: a chevron (right/down) now shows the
  state. New and reviewed differ by shape (filled dot / hollow ring) with a
  tooltip and accessibility label, not by colour alone.
- Width hints are updated only for expanded rows; updating all 500 rows on
  every layout pass slowed opening the full history to about 5 s.

## Verification

Screenshots of collapsed rows, an expanded row and the All filter at 380
points; `/ui` `scrollViewportWidth == windowWidth`; full `./Scripts/test.sh`.
