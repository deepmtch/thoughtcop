# BUG-046: Alarm color was permanent and ticker text was bold

## Symptom

The configured warning color filled the ticker during ordinary monitoring, so a
normal state looked like a permanent alarm. The scrolling message also used a
semibold font.

## Cause

The saved color was applied directly during launch and every color change,
without considering the selected message's evaluation state. `TickerView`
hard-coded `.semibold` for its message font.

## Fix

- Treat the saved color as the configured alarm color.
- Use a white background for pending, clear, failed, and ordinary history states.
- Apply the configured color only when the selected message is an actual alert.
- Restore white when navigating away from an alert or when a state clears.
- Render ticker message text with regular system-font weight.
- Rename appearance menu actions to **Alarm Color** and **Default Alarm Color**.

## Verification

`--ticker-background-selftest` verifies white normal state, configured and default
alarm colors, automatic foreground contrast, and non-bold ticker text.
