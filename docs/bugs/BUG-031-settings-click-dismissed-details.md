# BUG-031 — Clicking inside settings dismissed Thinkpeek details

## Symptom

With **What to Check** open, clicking inside its text editor or controls returned
the main HUD to the ticker and moved focus away from the editor.

## Root cause

BUG-030 classified clicks solely against the main HUD frame. The settings editor
is a separate Thinkpeek window outside that frame, so its local events were
mistaken for clicks outside the application.

## Fix

- Local mouse events belonging to a Thinkpeek window are always inside the app.
- Only global events from outside Thinkpeek can dismiss details.
- The existing screen-coordinate boundary remains for the main HUD.

## Verification

The outside-click regression test now proves that a click outside the HUD frame
but inside another Thinkpeek window is ignored, while an external click at the
same coordinates dismisses details.

After restarting the native app, a real system click inside **What to Check**
left `/ui.checkRulesEditorVisible == true`; the editor remained open and usable.
