# BUG-023: Ticker had no provider icons

## Symptom

The ticker showed a text source such as `Claude · appium` or `Codex · Thought
watch 2`, but no provider mark. At a glance, users could not distinguish Claude
from ChatGPT/Codex, and the top row lacked a clear visual hierarchy.

## Root cause

The ticker header only contained a source label and the right-side controls.
Provider detection and icon presentation did not exist.

## Fix boundary

- Added a focused `ProviderIconView` rather than adding provider logic to `HUD`.
- Detects Claude, Codex, and ChatGPT source prefixes.
- Uses the installed Claude and ChatGPT application icons when available.
- Falls back to accessible SF Symbols if either application is unavailable.
- Places the icon immediately before the source while preserving the flush-right
  placement/settings toolbar and the full-width message line.
- Keeps the toolbar above the provider, source, and ticker drawing layers so a
  provider transition cannot visually erase the controls.
- Invalidates and refreshes the unchanged toolbar during a provider transition;
  short, non-scrolling messages no longer depend on the ticker animation timer
  to make the controls reappear.
- Updates the icon whenever the selected ticker message changes.

## Verification

- `./.build/doublethink --provider-icon-selftest`
- `./build.sh`
- Running `/ui` reports `peekProvider` matching the visible source.
- Visual captures confirm the provider icon, source title, and right toolbar do
  not overlap at the fixed 460 × 70 ticker size.
