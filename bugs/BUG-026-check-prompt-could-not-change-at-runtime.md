# BUG-026: Check prompt could not change at runtime

## Symptom

Users could edit rule lines on disk, but could not change the checker's broader
instructions from the running app. The system prompt was compiled into the binary.

## Root cause

`DriftCheck.swift` used one global prompt constant and the settings UI exposed no
editor or persistent runtime preference.

## Fix boundary

- Add **Check Prompt…** to the compact settings menu.
- Present a native multiline editor with Save, Cancel, and Restore Default.
- Persist custom instructions in user defaults and read them for every new check.
- Keep the JSON-only response schema outside the editable text so parsing remains safe.
- Report the active prompt and customization state through `/ui`.
- Keep persistence, prompt assembly, editor UI, and menu routing in focused modules.

## Verification

`./thinkpeek --check-prompt-selftest` verifies default loading, custom persistence,
next-check prompt assembly, protected JSON instructions, and default restoration.
`./thinkpeek --settings-menu-selftest` verifies the runtime editor is discoverable.
