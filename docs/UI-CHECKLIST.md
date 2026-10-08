# Thoughtcrime UI release checklist

This is the release gate for the borderless macOS HUD. Every applicable control
must be implemented, discoverable, accessible, and covered by a self-test or the
running `/ui` inspection surface. A checked item is not merely planned.

## Window lifecycle and escape routes

- [x] The ticker is one 28-point row (provider icon, chat name, text, History,
  Settings, Hide) and the stable resting state.
- [x] Full-message reader, controls, and history have a visible **Done** action
  that returns to the ticker.
- [x] The ticker has a direct **Hide** action; **Quit Thoughtcrime** is always in the
  menu-bar menu.
- [x] Escape from reader, controls, or history returns directly to ticker.
- [x] Command-Q activates Quit while a detail view owns focus.
- [x] Clicking outside the full-message reader returns to ticker.
- [x] Closing details restores the previously active application.
- [x] No intermediate **Collapse** state or keyboard-only trap remains.

## Content and state

- [x] Ticker always identifies the exact source/session.
- [x] Concurrent activity identifies every working/waiting session; one source
  cannot visually hide another active Claude or Codex session.
- [x] Ticker identifies Claude and ChatGPT/Codex with their provider icon.
- [x] Empty or formatting-only summaries cannot replace readable text.
- [x] Operation-start placeholders do not replace useful content.
- [x] Single click opens the complete message; it does not open settings.
- [x] Full message renders supported inline Markdown.
- [x] Overflowing ticker text remains rendered throughout the scroll cycle.
- [x] Reduce Motion produces stationary clipped text.
- [x] Current mode is inspectable as ticker, message, or history.
- [x] The ticker toolbar is History, Settings and Hide; clicking the text opens
  the reader, whose History button opens history.

## Navigation and history

- [x] **Latest** returns full history to new content.
- [x] Session picker supports automatic and explicit-session selection.
- [x] Unseen/history state is labeled instead of silently changing selection.
- [x] Expanded history has a visible selected row and supports Up/Down, J/K,
  Home/End, Return, and Space without stealing keys from text controls.
- [x] The reader has one row of tabs: All first, up to two chats (the open
  one always shown), then "+N ▾" listing the rest; Live / Paused and "Jump to
  latest" sit beside Done. Other sessions show "(N new)" and never replace
  the message being read.
- [x] History is newest first; "↑ N new" appears only when unseen items are
  above, and Up/k/Home move toward newer items there.
- [x] Controls, reader and history share one 380-point width; the Window Width
  setting sizes only the ticker.
- [x] Every history item is a two-line row; the reader shows quote, Why, then the
  full message once.
- [x] Usage Today in the menu-bar menu opens a Usage window with provider-reported
  tokens and provider-published prices; a missing price is shown as missing.
- [x] Violation History offers 10/25/50/100/250/500 newest (default 50) with the
  current choice checked; lowering it removes deleted violations' cards.
- [x] Confirm with Second Check is a checked toggle (default on); rejected
  claims never appear in the ticker, history, badge, or store.
- [x] Violation history distinguishes **New** from **Reviewed** and has a real
  empty state plus an explicit storage-error state.

## Settings

- [x] One Settings window (menu bar › Settings… ⌘,, and both ⚙ buttons) with
  General, Alerts, Rules and Keys toolbar tabs; General and Alerts apply at
  once, toggles are switches with a one-line description.
- [x] What to Check uses local app storage as its only source of truth.
- [x] No triggers file or file path remains in the UI or runtime configuration.
- [x] Rules and Keys keep horizontal Revert/Save controls; Return inserts a
  newline, Command-S saves, the window stays open after Save, switching tabs
  keeps typed text, and closing with unsaved edits requires a decision.
- [x] Ticker speed offers Slow, Normal, and Fast and persists the choice.
- [x] Width offers Narrow and Standard, supports drag resize, and persists.
- [x] Position offers six Top/Bottom × Left/Center/Right presets.
- [x] Six Top/Bottom × Left/Center/Right positions are in Settings › General;
  the ticker has no corner arrows.
- [x] Top positions touch the menu bar (no gap), with only the bottom corners
  rounded; bottom positions keep a 12-point margin.
- [x] The violation color uses the native color picker and persists; it colors
  the menu-bar flash.
- [x] The ticker always uses the semantic macOS window surface; a violation
  never changes its background.
- [x] System-background reset is available.
- [x] Foreground text/icons automatically maintain light/dark contrast.
- [x] Two persisted switches: Flash menu-bar icon red (default on, 3 s) and Show
  bubble (default off, 5 s, after the flash when both are on; top right when
  macOS hides the icon; opens the violation on click). Neither changes the
  ticker selection or a hidden window.
- [x] Show Last Violation sits directly below Open Violation History… and opens
  the newest violation in the reader ("No violations yet." when none).
- [x] Resting the mouse on the menu-bar icon for 0.5 s shows the last violation
  in the bubble (time on its last line); it stays while the mouse is on the
  icon or bubble, hides 0.5 s after, gives way to the menu and to a new
  violation's alert, and opens the violation on click.
- [x] History tabs All | Violations | Archive: Violations holds the last hour
  by record timestamp; older ones move to Archive at the exact boundary, each
  tab with its own empty state.
- [x] Provider credentials use native secure fields, are never prefilled, and
  distinguish keep, replace, and remove actions without displaying key values.

## Input, focus, and accessibility

- [x] Hover never changes view or window geometry.
- [x] Detail views explicitly own keyboard focus while open.
- [x] Ticker relinquishes keyboard focus when restored.
- [x] Every icon-only control has a tooltip and accessibility label.
- [x] Provider icons expose an explicit provider accessibility label.
- [x] Session, status, message position, history, and lifecycle controls have
  explicit accessibility names instead of relying on symbol pronunciation.
- [x] Done, Hide, and Quit have unambiguous placement, labels, and shortcuts.
- [x] Enabled violation popups post a high-priority VoiceOver announcement with
  source and reason; disabled popups remain silent and non-interrupting.
- [x] New unreviewed violations give the menu-bar shield an explicit semantic
  alert tint in addition to its count and accessible label.
- [x] Source labels truncate safely and retain full text in a tooltip.
- [x] Text remains selectable in the full-message reader.
- [x] Controls reflow at narrow width instead of clipping.

## Window behavior and layout

- [x] Borderless ticker has no accidental title-bar height.
- [x] Window remains inside the screen's visible frame.
- [x] Position remains anchored during height/width transitions.
- [x] Ticker width and height stay fixed while resting.
- [x] Controls/message width remains within 380–560 points.
- [x] Full history is capped at 700 points and scrolls vertically.
- [x] Horizontal scrolling is disabled for wrapped content.
- [x] Outside-click dismissal ignores clicks inside the panel.

## Intentionally not applicable

- [x] Minimize and Zoom: this is a transient HUD, not a document window; ticker
  and Close are its compact/minimized behaviors.
- [x] Check-prompt edits support Undo and dirty-close confirmation.
- [x] Destructive confirmation: Close preserves monitoring; Quit deletes no data.
- [x] Standard traffic lights: replaced by explicit Done/Hide because the
  resting HUD is intentionally borderless; Quit remains in the menu bar.

## Automated gates

- [x] Layout, presentation, source, ticker, color, message, outside-click,
  placement, chrome, width, and interaction self-tests.
- [x] Escape/no-Collapse self-test plus a real installed Escape event.
- [x] Exit-control labels, accessibility names, and callback self-test.
- [x] Running `/ui` state and `/screenshot` visual verification for each mode.
- [x] The UI API requires bearer authentication, rejects mutating GET requests,
  and binds only to IPv4 loopback.
