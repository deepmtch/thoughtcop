# BUG-093 — Segmented reader tabs were unreadable

## Evidence

User screenshot (2026-10-03): the reader's session tabs, an
`NSSegmentedControl`, cut every name to a few letters in equal slices, and the
segment dividers ran into the labels. The user approved a chips mockup.

The first chip build, captured in the Parallels guest, drew each title flush
against the chip's left edge ("EU brand finder app mockup" touched both
edges), left "All" uncentred, and started the chip row 4 pt left of the
Live / Paused line.

## Root cause

A segmented control gives every segment the same width, whatever the name
length. A borderless `NSButton` draws its title from the left edge of its
bounds, with no inset.

## Fix

`SessionChipsView` shows one rounded chip per chat. Each chip is as wide as its
name but at most half the row, and long names are truncated at the end. Chips
wrap onto new rows. The full name is in the tooltip and the accessibility
label. `ChipCell` draws the working dot and the title centred, inside 10 pt of
side padding. It uses one layout function, `contentLayout(in:)`, which `/ui`
also reports. The chip row uses the status line's 16 pt leading edge.

## Verification

- `/ui` `readerTabFrames` now carries each chip's frame and its drawn content.
  `Scripts/capture_screens.py` asserts four things for every capture:
  - each chip stays inside the reader;
  - no chip is wider than half the row;
  - chips on the same row do not overlap;
  - the dot and title keep 10 pt to each edge.
- A build with 1 pt padding fails: "04-reader-two-working: tab chip text
  touches its edge". The fixed build passes the full suite in the Parallels
  guest, and all 17 captured screens were reviewed by eye.
