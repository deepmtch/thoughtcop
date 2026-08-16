# BUG-052: checker requests had no visible activity signal

## User-visible failure

The ticker gave no direct indication that a reasoning item was being sent to the
configured checker. Users could not distinguish an active network evaluation
from an idle monitor.

## Fix

- Show a small filled-lightbulb indicator in the ticker header only after an
  external provider request actually starts.
- Give the indicator a tooltip and accessibility label naming the destination.
- Hide it when all concurrent checks finish, after an 800 ms minimum visible
  duration so a fast provider response does not make the signal imperceptible.
- Publish the same in-flight state through the local UI API.
- Record the actual reasoning event type in the content-free privacy audit
  instead of the obsolete `reasoning_summary` label.

## Verification

The ticker-actions self-test verifies visible, hidden, destination, and
accessibility states. The privacy-audit self-test verifies the outbound record
type without logging reasoning content.
