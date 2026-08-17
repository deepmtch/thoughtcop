# BUG-066: Multi-session test expired its fixtures

Status: Fixed

## Failure

The black-box test observed Claude and Codex start events, then timed out before
either reasoning record reached the checker or ticker.

## Root cause

Its synthetic transcript records used fixed August 16 timestamps. Transcript
discovery uses record timestamps to decide whether a session is active. Once the
calendar advanced, a periodic rescan correctly removed those fixtures and their
tailers before the test appended reasoning.

## Fix and verification

Every synthetic event timestamp is now derived from the test's UTC start time.
The test again passes all four simulated conversations, concurrent Claude/Codex
activity, exact checker payload exclusions, alert and clean results, ticker
navigation, session switching, and reader freeze/resume behavior.

