# BUG-091 — Reader tabs broke with real session names

## Evidence

User screenshot (2026-10-03): the reader with tabs stretched across the whole
screen; tabs read "reserach grants", "2 active", "● Clipboard image generation
shortcut", "● Codex/ChatGPT configuration storage · agent a3ae426c"; the body
said "No readable message from this session yet." The feature had been
verified only with two short names ("Alpha", "Beta").

## Root causes

1. The segmented control demanded every full label's width, so long names
   widened the window far beyond 380 points.
2. With two chats working and no readable message, the aggregate status label
   "Claude · 2 active" was taken as a session and became a tab.
3. Sub-agents ("<chat> · agent <id>") got their own tabs, and up to four chats
   plus All made every label unreadable at 380 points.
4. The working mark was a text "●" (always white inside a tab).
5. A violation from a reply rendered its reader text as plain text, showing
   literal `**` markers.
6. The ticker header truncated in the middle, showing only a sub-agent ID at
   narrow width.

## Fix

Tabs share the reader width and truncate (low compression resistance, fixed
segment widths); an aggregate status opens the reader on All; sub-agents
belong to their chat's tab; at most three chat tabs plus All in a stable
order; a green dot image marks working chats; violation and failure readers
always render formatted text; the ticker shows the chat name with tail
truncation and the full source as tooltip.

## Verification

`Scripts/capture_screens.py` (now part of `./Scripts/test.sh`, run in the
Parallels guest) captures all 16 screens with realistic data — long titles,
five sessions including a sub-agent, chats working without readable messages —
and asserts detail views are 380 points, at most 3 chat tabs plus All, no
sub-agent or aggregate tab, and no markdown markers in the rendered reader.
All 16 screenshots were reviewed by eye.
