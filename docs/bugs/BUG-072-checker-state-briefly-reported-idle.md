# BUG-072: Checker state briefly reported idle

Status: Fixed

## Reproduction evidence

The black-box test added a Claude Desktop response and thinking record together.
The ticker displayed the thinking while `/ui` briefly reported
`checkerRequestInFlight: false`; reading the audit at that point found five of six
reasoning outcomes. The provider callback later produced the missing outcome.

## Root cause

Thinkpeek added an evaluation token only inside the asynchronous
`requestStarted` callback. Evidence had already been accepted and displayed before
that callback reached the main queue, creating a false-idle window.

## Fix boundary

The evaluation token and visible activity indicator are now started together,
synchronously when evidence is accepted. The provider callback can still refine
the displayed destination if fallback changes it. Completion removes the same
token and clears the indicator after the final active evaluation.

## Verification

The multi-session black-box test waits on `checkerRequestInFlight == false` before
requiring all request/result audit pairs. This now covers back-to-back response
and thinking evaluation without a false-idle state.
