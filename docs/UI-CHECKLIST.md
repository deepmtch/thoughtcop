# Thinkpeek UI release checklist

This is the release gate for the borderless macOS HUD. Every applicable control
must be implemented, discoverable, accessible, and covered by a self-test or the
running `/ui` inspection surface. A checked item is not merely planned.

## Window lifecycle and escape routes

- [x] One-line ticker is the stable resting state (460 × 70 points).
- [x] Full-message reader has visible **Done** and **Quit** actions.
- [x] Controls and full history have an always-visible **Close** action.
- [x] Controls and full history have an always-visible **Quit** action.
- [x] Escape from reader, controls, or history returns directly to ticker.
- [x] Command-Q activates Quit while a detail view owns focus.
- [x] Clicking outside the full-message reader returns to ticker.
- [x] Closing details restores the previously active application.
- [x] No intermediate **Collapse** state or keyboard-only trap remains.

## Content and state

- [x] Ticker always identifies the exact source/session.
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

## Settings

- [x] Ticker speed offers Slow, Normal, and Fast and persists the choice.
- [x] Width offers Narrow and Standard, supports drag resize, and persists.
- [x] Position offers six Top/Bottom × Left/Center/Right presets.
- [x] Top positions use the macOS visible frame below the menu bar.
- [x] Ticker background uses the native color picker and persists opacity.
- [x] System-background reset is available.
- [x] Foreground text/icons automatically maintain light/dark contrast.

## Input, focus, and accessibility

- [x] Hover never changes view or window geometry.
- [x] Detail views explicitly own keyboard focus while open.
- [x] Ticker relinquishes keyboard focus when restored.
- [x] Every icon-only control has a tooltip and accessibility label.
- [x] Session, status, message position, history, and lifecycle controls have
  explicit accessibility names instead of relying on symbol pronunciation.
- [x] Close and Quit use visible text, tooltips, accessibility names, shortcuts.
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
- [x] Save, Open, Undo, and dirty-document warnings: no document is edited.
- [x] Destructive confirmation: Close preserves monitoring; Quit deletes no data.
- [x] Standard traffic lights: replaced by explicit Close/Quit because the resting
  HUD is intentionally borderless.

## Automated gates

- [x] Layout, presentation, source, ticker, color, message, outside-click,
  placement, chrome, width, and interaction self-tests.
- [x] Escape/no-Collapse self-test plus a real installed Escape event.
- [x] Exit-control labels, accessibility names, and callback self-test.
- [x] Running `/ui` state and `/screenshot` visual verification for each mode.
