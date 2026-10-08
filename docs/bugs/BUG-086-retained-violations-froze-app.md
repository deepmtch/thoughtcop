# BUG-086 — Retained violation history froze the app

## Evidence

On 2026-10-02 the running app (commit `a154abf`) showed the macOS spinning
cursor on every click. `/usr/bin/sample` of the live process:
`HUD.applicationDidFinishLaunching` → `HUD.restoreViolationCards` →
`HUD.addCard` → Auto Layout `NSISEngine` constraint solving, 100% CPU for more
than two minutes. `~/Library/Application Support/Thoughtcrime/violations.json`
held 388 records (383 from 2026-09-19/20, none reviewed). The app had not
launched successfully since 2026-09-04, so the stored history had not been
restored by any earlier build.

Isolated reproduction with 500 records (`ViolationStore.maximumRecords`),
`Scripts/test_violation_restore_e2e.py`:

| Build | Launch | Each new live record |
|---|---|---|
| Empty history | 0.5 s | 0.06–0.23 s |
| `a154abf`, 500 records | no first state within 120 s | — |
| Visibility applied once per bulk add | 5.4–6.1 s | 2.8–3.1 s |
| Hidden cards detached from the stack | 4.9 s | 0.17–0.23 s |
| Detached card changes not laid out/published | 2.0–2.3 s | 0.12–0.23 s |

## Root cause

1. `addCard` re-applied visibility to every existing card on each insertion, so
   restoring N records performed O(N²) `isHidden` changes and layout passes.
2. Hidden cards stayed in the feed `NSStackView`. A hidden arranged subview is
   detached from stack layout but keeps its subtree and constraints in the
   window's layout engine, so every later layout pass solved all 500 cards:
   about 3 s per new thought on the main thread.
3. Each restored card's content-change callback ran a full layout and
   `publishAPI` although the card was not displayed.

## Fix

- A new card starts hidden and outside the stack. Bulk adds (launch restore,
  initial history) apply visibility once at the end.
- `updateCardVisibility` attaches displayed cards and removes hidden ones from
  the stack (`syncCardAttachment`), restoring insertion order and the width
  constraint on attach. Records and card state are retained.
- `cardContentDidChange` ignores cards that are not in the stack.
- `showAlert` updates the violation menu and badge immediately after storing
  the record. It previously called `updateCardVisibility` (which publishes)
  first, so `/ui` briefly reported the new `violationCount` with the previous
  badge. The removed per-card publish had masked this; the multi-session test
  then failed 2 of 5 runs, and passes 6 of 6 after the reorder.
- `/ui` keeps `cardCount` (all cards plus the empty state, as before) and adds
  `attachedCardCount`.

## Verification

`Scripts/test_violation_restore_e2e.py` (in `./Scripts/test.sh`) launches with
500 stored violations and requires launch < 5 s, live records < 1 s in the
ticker before and after opening history, at most two attached cards in the
ticker, 505 visible cards in All and 500 in Violations. Limits are about 2× the
fixed launch and 5× the empty-history live latency. Screenshots of the ticker,
All history and Violations history show full-width cards in order.

## Known limit

With full history open, all 500+ cards are attached: opening takes about 2 s
and each new live record about 3 s while it stays open. Removing that needs a
virtualized history list.
