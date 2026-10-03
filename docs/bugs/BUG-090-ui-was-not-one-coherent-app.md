# BUG-090 — The UI was not one coherent app

## Evidence

Parallel visual review of all 14 screens captured in the Parallels guest
(2026-10-02/03): window width jumped between 380, 510, 560 and 590 points;
the compact controls contained a message card plus debug text ("checked by
Dummy · deterministic-checker in 12 ms") although the UI checklist forbids
it; history mixed compact rows with large bordered cards; the violation reader
repeated the quote and had a red-tinted surface; the empty Violations view had
a shield, title, button and an unrelated "Watching…" card; the rules editor
was ~740 points wide (a single-line help label); the provider-keys window cut
off its placeholder, offered "Remove saved key" with nothing saved, and showed
`.env` jargon; five terms named one concept; the ticker ignored the Narrow
width setting; cost was not visible anywhere.

## Fix (approved unified-UI and usage mockups)

- One detail width (380 pt) for controls, reader and history; the Window Width
  setting sizes the ticker (Narrow 400 / Standard 560).
- Compact controls: navigation and settings only, no card, no dead space.
- Every history item is a two-line row (grey dot for messages, red dot / ring
  for new / reviewed violations); rows expand in place. Today's times show as
  "20:24".
- Violation reader: "Violation", the quote, "Why: …", then the full message
  once (omitted when it equals the quote); normal surface with a red stripe.
- Empty Violations: one line, "No violations yet."; status cards never appear
  in the Violations filter.
- Rules editor: 460 pt, wrapped help, "Rules" / "Save Rules" (accent),
  "All text is one rule" / "Each line is its own rule".
- Provider keys: full-width fields, placeholder matching the saved state,
  Remove only when a Keychain key exists, plain status lines.
- Menu: "Edit Rules…", "Provider Keys…", and "Usage Today: $… · N checks…"
  opening a Usage window (today / this month from provider-reported tokens ×
  provider-published price; "price not published" when unavailable).

## Regressions found and fixed while doing this

- With no card in compact mode the feed was always "near bottom", so adding a
  message scrolled-to-latest and replaced the open reader. Scroll-following is
  now limited to the expanded history.
- Usage pruning used the record's date; a back-dated record deleted the
  current month. Pruning is relative to now.

## Verification

`./Scripts/test.sh` in the Parallels guest (new `--usage-selftest`), and all
15 screens recaptured in the guest and reviewed.
