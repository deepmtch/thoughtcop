# BUG-047: settings and exit actions were hidden

## User-visible failure

Changing display settings from the resting ticker required opening the expanded
controls view first and then finding its gear button. In expanded readers and
controls, the action that returned to the ticker was ambiguously labelled
`Done`, while `Quit Thoughtcrime` was hidden behind an ellipsis menu.

## Root cause

The ticker exposed check-rule editing and message navigation but did not own a
display-settings launcher. `DetailExitControls` also treated Quit as an overflow
action even though the borderless panel has no standard macOS title-bar close or
application-menu affordance.

## Fix boundary

- Add a dedicated, one-click display-settings gear to the resting ticker.
- Keep the same hierarchical display menu and command path in both launchers.
- Label the return action `Close` and render `Quit` beside it in every expanded
  presentation; remove the lifecycle overflow menu.
- Preserve Escape for Close and Command-Q for Quit.

## Verification

- `--ticker-actions-selftest` verifies direct check-rule, display-settings, and
  navigation launchers with accessibility labels.
- `--exit-controls-selftest` verifies visible `Close` and `Quit` controls and
  both callbacks without an overflow step.
- The UI API test verifies the same close/quit state through the running app.
