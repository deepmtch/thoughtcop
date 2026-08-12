# BUG-004: Operation-start events replaced useful summaries

Status: fixed

## Observed behavior

`Claude operation started` or `Codex operation started` became the current card,
replaced the last useful peek text, and occupied a previous/next history slot.
The event contained no reasoning value for the user.

## Root cause

Activity records and readable reasoning records followed the same `addCard` path.
The code checked `kind == activity` only after constructing and selecting a card.
Backfilled activity records could also consume the configured history allowance.

## Fix

- Handle live operation-start records before card construction.
- Preserve the last readable summary and history selection.
- Signal pending work only through `● … working…` in the window title and the
  `operationPending`/`pendingSource` API fields.
- Clear the pending signal only when readable content arrives.
- Ignore backfilled operation-start records entirely.

## Verification

`./.build/thinkpeek --presentation-selftest` verifies the pending-work state machine,
including concurrent pending sources and clearing only after readable content.
An end-to-end window test then verified the card/history policy.

With one readable summary visible, a live operation-start record produced:

```text
cardCount: 2 (unchanged)
navigableCount: 1 (unchanged)
peekText: Previous useful summary must remain visible…
operationPending: true
windowTitle: ● Claude · activity · working…
```

After readable reasoning arrived, `navigableCount` became 2, the new summary was
selected, and `operationPending` returned to `false`.
