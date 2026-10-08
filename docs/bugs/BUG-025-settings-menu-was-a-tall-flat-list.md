# BUG-025: Settings menu was a tall flat list

## Symptom

Opening settings produced one tall menu containing speed, width, six positions,
and appearance actions. It obscured the screen and made unrelated choices look
like one undifferentiated list.

## Root cause

The pull-down button was populated by index with fourteen top-level items.

## Fix boundary

- Keep the settings button because it still owns persistent and center-position
  choices that do not belong in the resting ticker toolbar.
- Replace the flat list with four native submenus: Ticker Speed, Window Width,
  Window Position, and Appearance.
- Preserve checkmarks, icons, tooltips, callbacks, and all existing behaviors.
- Move menu construction and action routing out of `HUD` into
  `TickerSettingsMenu.swift`.

## Verification

`./.build/thoughtcrime --settings-menu-selftest` verifies four top-level categories and
the complete child-item structure. Existing speed, width, position, and color
tests continue to pass.
