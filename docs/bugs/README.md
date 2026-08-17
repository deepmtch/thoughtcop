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
| [BUG-036](BUG-036-short-message-opened-in-stale-tall-reader.md) | Short summary inherited a stale oversized reader height | Fixed |
| [BUG-037](BUG-037-detail-header-looked-like-debug-toolbar.md) | Detail controls looked like a dense two-row debug toolbar | Fixed |
| [BUG-038](BUG-038-automatic-checker-read-tool-records.md) | Automatic checker read tool calls and tool results instead of reasoning only | Fixed |
| [BUG-039](BUG-039-codex-reasoning-item-was-split-into-summary-lines.md) | Codex reasoning item was split into separate one-line messages | Fixed |
| [BUG-040](BUG-040-reasoning-only-boundary-had-no-runtime-audit.md) | Reasoning-only boundary had no content-free runtime audit | Fixed |
| [BUG-041](BUG-041-controls-were-empty-and-command-paths-diverged.md) | Controls hid the message and UI/API command paths diverged | Fixed |
| [BUG-042](BUG-042-codex-summary-markdown-made-every-line-bold.md) | Codex summary Markdown made every reasoning line bold | Fixed |
| [BUG-043](BUG-043-plaintext-provider-reasoning-was-not-preferred.md) | Plaintext provider reasoning was not preferred over summaries | Fixed |
| [BUG-044](BUG-044-summary-only-history-stalled-startup.md) | Summary-only history stalled startup and left the interface empty | Fixed |
| [BUG-045](BUG-045-ticker-background-used-hand-cursor.md) | Ticker background used a hand cursor | Fixed |
| [BUG-046](BUG-046-alarm-color-was-permanent-and-ticker-text-was-bold.md) | Alarm color was permanent and ticker text was bold | Fixed |
| [BUG-047](BUG-047-settings-and-exit-actions-were-hidden.md) | Display settings required opening controls and Quit was hidden in overflow | Fixed |
| [BUG-048](BUG-048-check-prompt-used-checklist-icon.md) | Check-prompt editing used an ambiguous checklist icon | Fixed |
| [BUG-049](BUG-049-launchctl-created-relaunch-loop.md) | Post-commit launch jobs made app instances continuously replace each other | Fixed |
| [BUG-050](BUG-050-plaintext-reasoning-bypassed-checker.md) | Plaintext Claude and Codex reasoning displayed but silently bypassed the checker | Fixed |
| [BUG-051](BUG-051-app-bundle-lost-env-configuration.md) | App-bundle restart looked for `.env` inside the bundle and disabled checking | Fixed |
| [BUG-052](BUG-052-checker-request-had-no-visible-activity.md) | External checks had no explicit in-flight indicator in the ticker | Fixed |
| [BUG-053](BUG-053-checker-outcome-not-persisted.md) | Checker requests had no durable paired outcome record | Fixed |
| [BUG-054](BUG-054-encrypted-records-replaced-useful-ticker.md) | Encrypted records repeatedly replaced useful ticker content with a placeholder | Fixed |
| [BUG-055](BUG-055-multi-session-flow-lacked-black-box-test.md) | Concurrent Claude/Codex checker and ticker behavior lacked a black-box test | Fixed |
| [BUG-056](BUG-056-hidden-encrypted-history-stalled-startup.md) | Hiding encrypted history caused finite backfill to scan entire large rollouts | Fixed |
| [BUG-057](BUG-057-ui-api-bind-race-after-restart.md) | Replacement restart could silently lose the local UI API listener | Fixed |
| [BUG-058](BUG-058-transcript-discovery-blocked-main-thread.md) | Startup and periodic transcript discovery froze the UI thread | Fixed |
| [BUG-059](BUG-059-claude-title-did-not-match-desktop.md) | Claude ticker title could differ from Claude Desktop's conversation title | Fixed |
| [BUG-060](BUG-060-touched-transcript-looked-active.md) | A touched old transcript looked like the active conversation | Fixed |
| [BUG-061](BUG-061-provider-activity-was-invisible.md) | Provider activity was invisible when no plaintext reasoning arrived | Fixed |
| [BUG-062](BUG-062-claude-question-remained-working.md) | Claude question remained stuck in working state | Fixed |
| [BUG-063](BUG-063-old-cloud-cache-replayed-as-live.md) | Old Claude cloud cache replayed as live activity | Fixed |
| [BUG-064](BUG-064-headless-check-truncated-audit.md) | Headless check truncated the live privacy audit | Fixed |
| [BUG-065](BUG-065-claude-desktop-thinking-was-not-captured.md) | Claude Desktop plaintext thinking was not captured | Fixed |
