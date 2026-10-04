# BUG-095 — Settings were hidden in nested menus

## Evidence

The user's screenshots (2026-10-04) showed three problems:

- The only way to change a setting was the ticker's ⚙ pop-up menu, with
  submenus two levels deep.
- The menu-bar menu had no Settings item.
- ⌘, opened "Edit Rules…" instead of Settings.

The user asked whether this is best practice. It is not: macOS menu-bar apps
offer **Settings… (⌘,)**, which opens one tabbed Settings window. The user
approved a mockup of that pattern.

## Root cause

Settings grew one menu at a time: the ticker ⚙ menu (`TickerSettingsMenu`),
plus separate Rules and Provider Keys windows reached from the menu bar. There
was never a single Settings surface.

## Fix

- **One window.** `SettingsWindow` is a preference-style window with
  General, Alerts, Rules and Keys toolbar tabs. Menu bar › **Settings… ⌘,**
  and both ⚙ buttons open it, and 💬 opens it on Rules. "Edit Rules…" and
  "Provider Keys…" are gone from the menu bar, and `TickerSettingsMenu` is
  removed.
- **General and Alerts apply immediately.** They hold popups and switches,
  each with a one-line description, and refresh from the same single point as
  before (`updateSettingsMenuChecks`).
- **Rules and Keys are tabs now.** They keep Save; Cancel became **Revert**,
  because Settings stays open after saving. Keys re-reads the Keychain status
  after a save. Switching tabs keeps typed text, and closing the window with
  unsaved edits asks first.
- **API.** New routes `/settings`, `/settings/{general,alerts,rules,keys}` and
  `/settings/close`. The `/check-rules` and `/provider-credentials` routes
  still work. `/ui` adds `settingsVisible`, `settingsTab`, `settingsTabs` and
  the current value of each control.

## Verification

- **Self-test:** `--settings-window-selftest` checks the tab order, that each
  switch and popup calls its handler, tab selection, and the alert preference
  defaults. `--check-rules-editor-selftest` checks Revert/Save and that the
  editor is clean after saving.
- **Screens:** `capture_screens.py` captures all four tabs, including the
  window's tab toolbar, and checks:
  - the menu-bar menu items;
  - that the Alerts switch matches the stored setting.
  The full suite passes in the Parallels guest, and all screens were reviewed
  by eye.

## Found while verifying

- **Empty window title.** The window title was empty; it now names the
  selected tab, including after a click on a toolbar tab. The capture asserts
  the title for each tab.
- **Slow refreshes.** The 500-violation restore test measured 1.08 s for a live
  record (limit 1.0 s). The violation tabs added in BUG-094 parsed every stored
  record's timestamp on each refresh, with two new date formatters per parse.
  Record times are now cached per record and the formatters are shared. The
  same test now measures 0.11–0.32 s live and 2.1 s at launch, down from 2.6 s.
