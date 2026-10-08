# BUG-027: Rules had competing app and file storage

## Symptom

The runtime editor and `triggers.txt` created competing sources of truth. Its
oversized alert also showed an irrelevant folder icon and stacked three
full-width buttons.

## Root cause

BUG-026 introduced a preference-backed prompt rather than editing the rule file
that the checker already reloads for every request.

## Fix boundary

- Remove both triggers files and the environment path override.
- Store rules only in the stable `com.thoughtcop.app` local preference domain.
- Preserve the user's current rule as the built-in initial value.
- Use locally saved rules automatically on the next check.
- Replace the alert with a compact nonmodal editor and horizontal Save/Cancel buttons.
- Expose local content, count, customization, and editor visibility in `/ui`.
- Expose `/check-rules` for deterministic editor opening; `/screenshot` captures the
  editor while it is visible so the actual native layout can be regression-checked.

## Verification

`./.build/thoughtcop --check-rules-editor-selftest` uses isolated app preferences to verify
the initial rule, file-free local persistence, next-check semantics, and compact
horizontal actions.
