# BUG-032 — Primary check instruction was nested in settings

## Symptom

Editing what Thinkpeek checks required opening the sliders menu and then finding
**What to Check…**. The app's primary configuration task was presented like an
infrequent appearance preference.

## Design decision

Apple's toolbar guidance prioritizes frequent primary commands, while its settings
guidance recommends keeping generic settings out of toolbars. **What to Check** is
the core monitoring task, not a generic display preference.

## Fix

- Add a dedicated checklist button to the ticker toolbar.
- Open **What to Check** directly from that button in one click.
- Keep the sliders button for navigation, speed, width, position, and appearance.
- Retain **What to Check…** in the menu as a secondary discoverable route.
- Provide a tooltip and the accessibility label **Edit what to check**.

## Verification

The ticker-action regression test invokes both direct actions and verifies their
accessibility names. Live UI state exposes the ordered actions for end-to-end
inspection.

Installed verification reported the toolbar actions as `Edit what to check`,
`Open controls and settings`. Opening the editor and posting a real click inside
it left `checkRulesEditorVisible == true`.
