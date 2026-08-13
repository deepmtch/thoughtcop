# BUG-031 — Prompt editor disappeared when clicked

## Symptom

The **What to Check** editor appeared, but clicking its text area, mode selector,
Save, or Cancel could make the editor disappear behind the previously active app.

## Root cause

The main HUD's global outside-click monitor remained active while the separate
prompt editor was visible. An editor click is outside the HUD's frame, so the HUD
ran its Close transition and reactivated the application that had focus before
Thinkpeek. That focus transfer hid the editor.

## Fix

The dismissal decision now receives the prompt editor's explicit visibility
state. While the editor is visible, HUD outside-click dismissal is disabled.
Save and Cancel remain the only editor dismissal actions. Once the editor closes,
ordinary outside clicks again return HUD details to the ticker.

## Verification

The regression test covers four explicit states: inside HUD, visible editor,
ordinary outside click, and ticker already active. The full application regression
suite must pass before deployment.
