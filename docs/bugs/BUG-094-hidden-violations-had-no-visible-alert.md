# BUG-094 — A violation while hidden had no noticeable alert; old violations crowded the list

## Evidence

The user (2026-10-04): with ThoughtCop minimized, the only sign of a new
violation was the menu-bar shield changing shape. The optional 10-second ticker
popup did nothing while the window was hidden (BUG-074 forbids reopening it).
The user asked for:

- one setting that turns the menu-bar icon red for 3 seconds and then shows a
  bubble;
- a menu item that shows only the last violation, below the violation history
  item;
- a Violations list limited to the last hour, with everything older in an
  Archive tab.

The user approved the mockups as drawn ("do it exactly like this").

The first build, checked in the Parallels guest with host `prlctl capture`,
drew the bubble off-screen. That guest's menu bar is full, so macOS hid the
ThoughtCop icon and parked its window off-screen, and the bubble was anchored
under it.

## Root cause

- **No alert while hidden.** The only opt-in alert was a takeover of the
  ticker, which is invisible while the window is hidden.
- **Crowded list.** The Violations tab listed every stored violation, whatever
  its age.
- **Off-screen bubble.** The bubble trusted the status item's window frame
  without checking that it was visible, and it kept only its x position inside
  the screen.

## Fix

- **One setting: "Flash Red, Then Show Bubble".** It uses the existing
  `violationAlertsEnabled` key, so an earlier opt-in carries over, and it
  stays off by default. On a new violation:
  - The shield and the count turn red for 3 s. `updateViolationMenu` honors the
    flash state, so a menu update during the flash cannot clear it.
  - The native foreground then returns: `restoreNativeStatusItemForeground`
    also resets the attributed count.
  - A non-activating bubble then appears for 5 s. It shows the session and the
    quoted evidence, and clicking it opens that violation in the reader.
  - A newer violation restarts both steps with its own content.
  - The ticker takeover and the beep are removed. The VoiceOver announcement
    stays.
- **Bubble placement.** The bubble is centred under the icon only when the
  icon's window is visible on a screen. Otherwise it appears at the top right
  of the main screen, below the menu bar. It is always kept inside the screen.
- **"Show Last Violation".** This item sits directly below "Open Violation
  History…" and opens the newest stored record in the reader. With no records,
  the reader says "No violations yet." A reader with no chat sessions no
  longer shows a lone "All" chip.
- **History tabs: All | Violations | Archive.**
  - Violations holds records whose transcript timestamp is less than 3600 s old
    (`violationIsArchived`).
  - A timer fires at the exact moment the oldest recent record turns one hour
    old, so it moves to Archive while history is open.
  - Counts come from the store, the same source as the badge.
  - A record with no readable timestamp is never archived and is counted in
    `/ui` as `withoutReadableTimestamp`. Checked records always have one,
    because only records written after launch are checked.
  - Archiving does not change the store, the retention limit, or the reviewed
    state.

## Verification

- **Lowest level:** `--violation-store-selftest` checks the exact boundary:
  59:59.999 is recent, 60:00 is archived, and an unreadable timestamp gives nil.
  `--settings-menu-selftest` checks the new title and the 3 s / 5 s durations.
  `--status-item-foreground-selftest` checks that the red count is reset.
- **Black box:** `test_multi_session_e2e.py` checks the full alert sequence:
  - setting off: nothing happens;
  - setting on and window hidden: first `statusItemFlashActive` with a red
    title, then the bubble with the evidence on screen, then both cleared;
  - throughout: `hiddenByUser` stays true and the ticker selection is
    unchanged;
  - afterwards: `/last-violation` opens the newest violation, and
    `/violation-bubble/open` opens the bubble's violation.
- **Screens:** `capture_screens.py` adds:
  - the bubble, checked to be on screen;
  - the Violations tab with exactly the last-hour records, and the Archive tab;
  - a stored record crossing the hour while history is open;
  - Show Last Violation, plus both empty states and the empty reader.
  The full suite passes in the guest, and all 21 screens were reviewed by eye.
- **Host captures in the guest:**
  - the bubble at the top right below the menu bar (the icon is hidden there);
  - the ⚙ › Violation Alerts submenu with the new item;
  - the menu-bar menu order, checked through the accessibility tree.
- **Not checked by eye:** the red icon. The guest's macOS 26 menu-bar settings
  hide the icon, and changing system settings is not allowed here. The app
  also cannot render its own menu-bar icon faithfully. The red state is
  checked through `/ui` only.

## Follow-up: "No violations yet." with active chats

With chats running and no violations, the first build opened that note as a
live reader on All. The next thought replaced it, and a later attempt showed
"Paused · message 1 of 2" and cut the note off. A fixed note now does not
follow live and shows no chips or status line (`readerShowsNote`). Moving to
any message clears it. `capture_screens.py` adds
`17b-reader-no-violations-with-chats`: it posts a thought after
`/last-violation` and asserts that the note stays and no chips are shown.

## Follow-up: flash and bubble are separate switches

The user (2026-10-04): "The flash and bubble are separate options and by
default the flash must be on and the bubble off."

- **Two switches.** `ViolationFlashPreference` (`violationFlashEnabled`,
  default on) and `ViolationBubblePreference` (`violationAlertsEnabled`,
  default off) replace the single switch. The bubble reuses the old key, so an
  earlier opt-in keeps the bubble on.
- **Order.** The bubble follows the flash when both are on, and appears at once
  when only the bubble is on.
- **Routes and `/ui`.** The routes are `/violation-flash/on|off` and
  `/violation-bubble/on|off`. `/ui` reports `violationFlashEnabled` and
  `violationBubbleEnabled`.
- **Tests.** The e2e asserts the defaults, then checks each case:
  - flash only: red, and no bubble at any point;
  - both: red, then the bubble;
  - bubble only: the bubble with no red step, opened by a click.

While verifying this, another tool typing in the shared Parallels guest sent
keys into the isolated test app and opened its reader (`appKit`-origin
"message" commands in the kept command log). Isolated mode now drops all real
keyboard and mouse input, and the restore test asserts its command log has no
`appKit`-origin commands.

## Follow-up: the flash was black, not red

In the user's first real violation (2026-10-04) the icon changed color, but to
black. macOS redraws template status-item images, their `contentTintColor`
and the title color in the menu bar's own foreground. The tests had only
checked that the tint was set.

- **Fix.** The flash is now a regular, non-template image: the shield and the
  count are drawn in the violation color from Settings › General (default
  red) by `statusFlashImage`.
- **Real check.** `imageDrawsColor` renders the image and requires pixels in
  that color. The status-item self-test runs it for red and for a custom
  color, and the e2e checks that the icon is non-template and drawn in the
  color during the flash, and a template again afterwards.
- **Speed.** The pixel check runs once per drawn image. Running it on every
  publish slowed launch with 500 stored violations past the 5 s limit.
