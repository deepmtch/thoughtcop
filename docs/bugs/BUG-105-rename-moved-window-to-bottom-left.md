# BUG-105: The rename moved the window to the bottom-left

## Symptom

After the app was renamed to Doublethink, the reader and ticker opened at the
bottom-left of the screen instead of under the menu bar where they had always
been.

## Evidence

User screenshot (2026-10-08): reader at the bottom-left. `defaults read
com.doublethink.desktop` showed the old position under
`NSWindow Frame thinkpeek.main-window` = `940 920 …` (top right, under the
menu bar) and a new `NSWindow Frame doublethink.main-window` = `60 218 …`.

## Root cause

The window's frame autosave name contained the app name. The rename changed it
from `thinkpeek.main-window`, so AppKit found no saved frame and used its
default placement, then saved that.

## Fix

The autosave name is an internal identifier and keeps its pre-rename value
(`MAIN_WINDOW_AUTOSAVE_NAME`), like the Keychain service. The legacy-migration
self-test asserts the value.

## Found while verifying

The full suite failed once with an isolated test app exiting by SIGTERM at the
exact second the real app was launched (pid start 22:46:33, test death 22:46:33).
The real app's single-instance guard matched every process named
`doublethink`, including isolated test instances. The guard now skips
processes started with `--isolated-e2e`.
