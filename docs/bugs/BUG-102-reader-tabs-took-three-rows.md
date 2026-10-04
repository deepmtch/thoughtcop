# BUG-102 — Reader tabs took three rows, with All last

## Evidence

The user's screenshot (2026-10-04) showed the reader with tabs on two rows
("guidelet new sarch", "reserach grants", then "Blog Frankfurt meetup…" and
"All"), plus a separate "● Live" line under them. The user asked whether this
was a good organization and approved the mockup: one row, All first, the
status beside Done ("now do this fix to the tabs only").

## Root cause

- Chips wrapped onto as many rows as the chats needed.
- All came after the chats.
- The Live / Paused status had its own line under the tabs.

## Fix

- **One row.** `SessionChipsView` lays the chips out on one row. All and
  "+N ▾" keep their natural width, and the chats share the rest.
- **Which chats show.** `readerTabLayout` shows at most two chats, and the
  open one is always among them. The rest are listed in the "+N ▾" menu.
  Order stays stable.
- **Selecting.** Tab 0 is All, then the shown chats, then the menu's chats
  (`/reader-tab/N`). `/ui` reports `readerOverflowTabs`.
- **Status.** Live / Paused and "Jump to latest" moved into the header row.

## Found while verifying

On the busy host, the capture's one-hour Archive step timed out: the record
moved to Archive about a minute late. App Nap throttled the background test
app's timers. Isolated runs now hold a `userInitiated` activity. The real app
is unchanged.

## Verification

- **Screens:** `capture_screens.py` asserts that tabs are on one row, All is
  first, there are at most four tabs, and chips stay in bounds and keep their
  padding.
- **Black box:** the reader-tabs and multi-session e2e tests check All first,
  "(1 new)" on a tab or in the menu, and switching tabs.
- **Host runs:** the full suite passed twice in a row on the host, and the
  reader screens were reviewed by eye.
