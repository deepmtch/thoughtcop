# BUG-071: History toolbar mixed settings with filters

Status: Fixed

## Reproduction evidence

Expanded history placed `All`, `Violations`, `Checks On`, a settings gear, and
`Latest` in one capsule. `Checks On` looked like a status or toggle but actually
opened the check-prompt editor. The gear opened ticker display settings even
though the user was reading history.

## Root cause

The detail toolbar reused the compact controls' check-prompt and display-settings
buttons without changing their visibility when entering expanded history.

## Fix boundary

Expanded history now contains only history controls: the All/Violations filter
and the always-visible Latest action. Prompt editing and display settings remain
available in compact controls, on the ticker, and through the local command API.
The history header remains fixed above the scrolling feed.

## Verification

The local UI API test asserts that prompt/settings controls are visible in compact
controls, absent from expanded history, and that Latest has the inverse visibility.
