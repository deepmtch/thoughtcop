# BUG-041: Controls were empty and command paths diverged

## Symptom

Opening controls hid the selected reasoning summary and presented only an
unstructured strip of icons. The local HTTP test endpoints called controller
methods through a different entry path than AppKit buttons, so an endpoint test
could not prove that the real UI command worked.

## Cause

Compact controls used the header height as the entire window height and hid the
feed whenever compact mode was active. UI callbacks invoked `HUD` methods
directly, while `UIStateServer` independently mapped HTTP strings to those same
methods.

## Fix

- Show the selected message under the compact toolbar at its exact rendered
  content height, capped at a 210-point scrolling viewport.
- Give message cards required vertical content hugging so the preview cannot
  stretch a short card and manufacture empty space above its status footer.
- Render card bodies with an intrinsically sized `NSTextView`; the previous
  `NSTextField` retained complete multi-paragraph text but painted only its first
  paragraph in the live card.
- Keep session/lifecycle controls on the first tier and group message navigation
  separately from instruction, display, and history actions.
- Use one plain gear button for the hierarchical display menu and a standard
  overflow menu for application lifecycle commands.
- Route AppKit clicks, keyboard dismissal, outside clicks, session selection,
  editor saves, settings, and HTTP endpoints through the same typed `UICommand`
  API.
- Reset a metadata-only `ui-api.jsonl` log at launch. It records only command
  name and origin, never prompt, rule, reasoning, session content, or animation
  frames.

No input-dependent heuristic is involved. The viewport and command mapping are
explicit UI structure.

## Verification

`--ui-command-api-selftest` proves AppKit and HTTP origins reach one handler and
that a secret rule value cannot appear in the command log.

`--two-summary-card-selftest` passes a two-paragraph Markdown summary through
the native card renderer and asserts the complete plain text and multi-line body
height.

`Scripts/test_ui_api.py` drives the running production window through
`/controls`, `/message`, `/previous`, `/screenshot`, and `/close`. It asserts a
nonempty selected-message viewport, frozen reader selection, preserved index,
valid PNG output, final ticker state, expected command records, and an allowlist
of metadata-only log fields.

The API publishes `initialScanComplete`; the runner waits for that explicit
boundary before issuing commands, so startup transcript backfill cannot block or
race the test.

`/ui` serves the API's last published snapshot directly from the server queue.
It does not dispatch a refresh to AppKit, so readiness remains observable even
while the main thread is completing the initial scan.
