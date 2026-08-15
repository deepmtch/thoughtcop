# Bug registry

User-visible regressions are recorded here with reproduction evidence, root cause,
fix boundaries, and verification. A bug document is committed with its fix.

| ID | Issue | Status |
|---|---|---|
| [BUG-001](BUG-001-fixed-width-text-wrapping.md) | Fixed-width text clipped instead of wrapping | Fixed |
| [BUG-002](BUG-002-compact-card-scroll-jump.md) | Compact card jumped to its footer and hid useful text | Fixed |
| [BUG-003](BUG-003-blank-position-menu.md) | Position control opened a tall blank menu | Fixed |
| [BUG-004](BUG-004-operation-start-replaces-summary.md) | Operation-start events replaced useful summaries | Fixed |
| [BUG-005](BUG-005-stale-process-after-rebuild.md) | Rebuilt binary left the old process on screen | Fixed |
| [BUG-006](BUG-006-peek-missing-source-session.md) | Collapsed summary omitted its source session | Fixed |
| [BUG-007](BUG-007-hover-loses-window-edge.md) | Hover expansion lost the chosen bottom/edge placement | Fixed |
| [BUG-008](BUG-008-hover-controls-feel-unavailable.md) | Delayed, drag-only peek made controls feel unavailable | Fixed |
| [BUG-009](BUG-009-wrapped-peek-too-tall-and-clipped.md) | Wrapped resting summary was too tall and clipped its first line | Fixed |
| [BUG-010](BUG-010-markdown-markers-in-ticker.md) | Markdown markers appeared literally in the ticker | Fixed |
| [BUG-011](BUG-011-hover-conflated-reading-and-controls.md) | Hover conflated reading a message with opening controls | Fixed |
| [BUG-012](BUG-012-ticker-speed-not-configurable.md) | Ticker reading speed was not configurable | Fixed |
| [BUG-013](BUG-013-title-bar-wasted-compact-height.md) | Title bar wasted compact HUD height | Fixed |
| [BUG-014](BUG-014-full-message-ignored-outside-click.md) | Full-message reader ignored outside clicks | Fixed |
| [BUG-015](BUG-015-empty-summary-erased-ticker.md) | Empty normalized summary erased the ticker | Fixed |
| [BUG-016](BUG-016-controls-width-was-fixed.md) | Controls window could not stay at a narrower width | Fixed |
| [BUG-017](BUG-017-ticker-background-not-customizable.md) | Ticker background was not customizable | Fixed |
| [BUG-018](BUG-018-ticker-animation-could-show-no-text.md) | Ticker animation could show no message text | Fixed |
| [BUG-019](BUG-019-layer-animation-left-undrawn-ticker-regions.md) | Layer-only scrolling left parts of ticker text undrawn | Fixed |
| [BUG-020](BUG-020-escape-left-controls-open.md) | Escape did not close every detail view directly to ticker | Fixed |
| [BUG-021](BUG-021-borderless-details-had-no-visible-exit.md) | Borderless controls/history had no visible Close or Quit | Fixed |
| [BUG-022](BUG-022-ticker-had-no-direct-position-controls.md) | Ticker had no direct edge-position controls | Fixed |
| [BUG-023](BUG-023-ticker-had-no-provider-icons.md) | Ticker did not visually distinguish Claude from ChatGPT/Codex | Fixed |
| [BUG-024](BUG-024-edge-icons-were-not-corner-controls.md) | Edge-docking icons were mistaken for corner placement | Fixed |
| [BUG-025](BUG-025-settings-menu-was-a-tall-flat-list.md) | Settings menu was an oversized flat list | Fixed |
| [BUG-026](BUG-026-check-prompt-could-not-change-at-runtime.md) | Check prompt could not be changed at runtime | Fixed |
| [BUG-027](BUG-027-editor-ignored-existing-local-rules-file.md) | Check rules had competing app and file storage | Fixed |
| [BUG-028](BUG-028-check-rules-save-used-wrong-preferences-domain.md) | Save wrote check rules to a preferences domain the app never read | Fixed |
| [BUG-029](BUG-029-user-instruction-was-reinterpreted-and-alerts-were-hidden.md) | Checker reinterpreted user text and detached warnings from their evidence | Fixed |
| [BUG-030](BUG-030-details-ignored-outside-click.md) | Controls and history ignored outside clicks | Fixed |
| [BUG-031](BUG-031-prompt-editor-dismissed-on-click.md) | Clicking in the prompt editor made it disappear | Fixed |
| [BUG-032](BUG-032-primary-check-instruction-was-nested-in-settings.md) | Editing the primary check instruction required two clicks through settings | Fixed |
| [BUG-033](BUG-033-open-reader-followed-new-messages.md) | Open reader replaced the message while the user was reading | Fixed |
| [BUG-034](BUG-034-check-failure-looked-like-user-warning.md) | Checker failure looked like a user warning from the monitored task | Fixed |
| [BUG-035](BUG-035-size-limit-was-misattributed-and-duplicated.md) | Local size limit was called a provider limit and repeated per instruction | Fixed |
