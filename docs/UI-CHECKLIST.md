# Thinkpeek UI release checklist

This is the release gate for the borderless macOS HUD. Every applicable control
must be implemented, discoverable, accessible, and covered by a self-test or the
running `/ui` inspection surface. A checked item is not merely planned.

## Window lifecycle and escape routes

- [x] One-line ticker is the stable resting state (510 × 70 points), wide
  enough to keep every primary action inside the visible panel.
- [x] Full-message reader, controls, and history have a visible **Done** action
  that returns to the ticker.
- [x] The ticker has a direct **Hide** action; **Quit Thinkpeek** is always in the
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
- [x] Current mode is inspectable as ticker, message, controls, or history.
- [x] Compact controls contain no message card or clipped content preview.

## Navigation and history

- [x] Previous and Next expose disabled states at boundaries.
- [x] Position indicator identifies selected message and total count.
- [x] **Show all** opens full history once and disappears there.
- [x] **Latest** returns full history to new content.
- [x] Restart returns ticker to the beginning and then closes controls.
- [x] Session picker supports automatic and explicit-session selection.
- [x] Unseen/history state is labeled instead of silently changing selection.
- [x] Expanded history has a visible selected row and supports Up/Down, J/K,
  Home/End, Return, and Space without stealing keys from text controls.
- [x] Violation history distinguishes **New** from **Reviewed** and has a real
  empty state plus an explicit storage-error state.

## Settings

- [x] Settings use compact Speed, Width, Position, and Appearance submenus.
- [x] What to Check uses local app storage as its only source of truth.
- [x] No triggers file or file path remains in the UI or runtime configuration.
- [x] Editor actions are horizontal Save/Cancel controls; Return inserts a
  newline, Command-S saves, and unsaved dismissal requires a decision.
- [x] Ticker speed offers Slow, Normal, and Fast and persists the choice.
- [x] Width offers Narrow and Standard, supports drag resize, and persists.
- [x] Position offers six Top/Bottom × Left/Center/Right presets.
- [x] Four direct corner-placement arrows stay visible in the ticker; six
  Top/Bottom × Left/Center/Right positions also remain in Display Settings.
- [x] Top positions use the macOS visible frame below the menu bar.
- [x] Ticker background uses the native color picker and persists opacity.
- [x] Normal mode uses the semantic macOS window surface; first-run violation
  mode uses a dynamic critical-red light/dark surface.
- [x] System-background reset is available.
- [x] Foreground text/icons automatically maintain light/dark contrast.

## Input, focus, and accessibility

- [x] Hover never changes view or window geometry.
- [x] Detail views explicitly own keyboard focus while open.
- [x] Ticker relinquishes keyboard focus when restored.
- [x] Every icon-only control has a tooltip and accessibility label.
- [x] Provider icons expose an explicit provider accessibility label.
- [x] Session, status, message position, history, and lifecycle controls have
  explicit accessibility names instead of relying on symbol pronunciation.
- [x] Done, Hide, and Quit have unambiguous placement, labels, and shortcuts.
- [x] New violations post a high-priority VoiceOver announcement with source
  and reason.
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
