# BUG-074: Violation reopened a user-hidden HUD

Status: Fixed

## Reproduction evidence

After the user hid the ticker, a new violation called `orderFrontRegardless()`
and brought the pink alert window back onscreen.

## Root cause

`showAlert` treated `!panel.isVisible` as permission to reveal the ticker. It did
not distinguish explicit user Hide from other visibility changes.

## Fix boundary

Thinkpeek now tracks explicit user-hidden state. New violations remain persisted,
unreviewed, badged in the menu bar, and available through history, but cannot
clear that state or reveal the window. Explicit Show Thinkpeek or Open Violation
History clears the state and presents the requested view.

## Verification

The isolated test hides the real AppKit window, emits a new alerting assistant
response, verifies `/ui.windowVisible == false`, then explicitly opens violation
history and verifies both violations are present.
