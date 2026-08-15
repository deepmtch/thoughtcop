# BUG-048: check-prompt editing used a checklist icon

## User-visible failure

The one-click action that edits the checker prompt used the `checklist` symbol.
That symbol suggested a task list or filter and did not communicate that the
button opens a text prompt editor.

## Root cause

The original control was named after the internal check-rules model instead of
the user action: editing a prompt.

## Fix boundary

- Use the native `text.bubble` symbol for the prompt editor in both the ticker
  and expanded controls.
- Name its tooltip and accessibility label `Edit check prompt`.
- Keep its existing one-click behavior and API command path unchanged.

## Verification

`--ticker-actions-selftest` verifies that the prompt action remains one click
and exposes the explicit `Edit check prompt` accessibility label.
