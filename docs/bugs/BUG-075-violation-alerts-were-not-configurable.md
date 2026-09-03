# BUG-075: Violation alerts were not configurable

Status: Fixed

## Reproduction evidence

A new evaluator match immediately replaced the visible ticker item, sounded an
alert, and posted a high-priority accessibility announcement. There was no
setting to keep monitoring non-interrupting.

## Root cause

Violation persistence and notification presentation were one unconditional
path. The menu bar tracked unread records, but no persisted preference separated
that durable signal from the transient popup, sound, and announcement.

## Fix boundary

Violation popups now use one persisted Boolean preference that defaults off.
Every violation is still stored and updates the unread menu-bar count and alert
tint. With alerts off, the current ticker selection, sound, and VoiceOver remain
untouched. With alerts on, the latest violation appears in the visible ticker
for 10 seconds and then restores the previous item. Explicit Hide and open
detail surfaces remain authoritative and are never interrupted.

## Verification

The settings self-test proves the default, persistence, exact 10-second policy,
menu hierarchy, and callback. The isolated black-box suite verifies default-off
non-interruption, opt-in transient presentation and restoration, and hidden-HUD
preservation through the running `/ui` state.
