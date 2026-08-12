# BUG-028: Check-rule Save used the wrong preferences domain

## Symptom

Pressing **Save** in **What to Check** closed the editor, but reopening it showed
the original rule. The running UI also continued to report
`checkRulesCustomized: false`.

## Reproduction evidence

- The editor showed the changed text and an enabled Save button.
- After Save, the `com.thinkpeek.app` preferences domain did not exist.
- The running `/ui` state still returned the built-in rule and
  `checkRulesCustomized: false`.

## Root cause

The production read path defaulted to `CheckRulesStore.localDefaults`, the
dedicated `com.thinkpeek.app` suite. The production write path accidentally
defaulted to `UserDefaults.standard`. Save therefore succeeded in a different
preferences domain that subsequent reads never consulted.

## Fix boundary

- Production `loadRaw`, `rules`, `saveRaw`, and `isCustomized` entry points now
  explicitly use the same local suite.
- Dependency-injected overloads remain available for isolated tests, but no
  production method has an independently selectable default store.
- The editor regression test now activates the actual Save button and verifies
  that its callback persists into the same injected store.

## Verification

- `Scripts/test.sh`
- `./.build/thinkpeek --check-rules-editor-selftest`
- Running `/ui` reports `checkRulesCustomized: true` after an editor save and
  returns the saved `checkRulesText`.
