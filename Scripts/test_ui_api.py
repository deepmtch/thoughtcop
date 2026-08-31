#!/usr/bin/env python3
"""Exercise the running AppKit UI only through Thinkpeek's local API."""

import json
import os
import time
import urllib.request
from pathlib import Path


BASE = os.environ.get("THINKPEEK_UI_API", "http://127.0.0.1:17321")
LOG = Path.home() / "Library/Logs/Thinkpeek/ui-api.jsonl"


def get(path: str) -> bytes:
    with urllib.request.urlopen(BASE + path, timeout=5) as response:
        if response.status != 200:
            raise AssertionError(f"{path}: HTTP {response.status}")
        return response.read()


def state() -> dict:
    return json.loads(get("/ui"))


deadline = time.monotonic() + 15
while time.monotonic() < deadline:
    if state().get("initialScanComplete") is True:
        break
    time.sleep(0.1)
else:
    raise AssertionError("initial transcript scan did not complete")

get("/controls")
time.sleep(0.15)
controls = state()
assert controls["uiStyle"] == "compact-controls", controls["uiStyle"]
assert 0 < controls["viewportHeight"] <= 210, controls["viewportHeight"]
assert controls["contentHeight"] > 0, controls["contentHeight"]
assert abs(controls["viewportHeight"] - min(210, controls["contentHeight"])) <= 1
assert controls["cardCount"] > 0, controls["cardCount"]
assert controls["closeControlVisible"] is True
assert controls["quitControlVisible"] is False
assert controls["quitControlInOverflow"] is False
selected_index = controls["currentIndex"]

get("/message")
time.sleep(0.15)
reader = state()
assert reader["uiStyle"] == "full-message", reader["uiStyle"]
assert reader["messageReaderFrozen"] is True
assert 118 <= reader["windowHeight"] <= 420, reader["windowHeight"]
assert reader["closeControlVisible"] is True
assert reader["quitControlVisible"] is False
assert reader["quitControlInOverflow"] is False

get("/controls")
time.sleep(0.15)
returned = state()
assert returned["uiStyle"] == "compact-controls"
assert returned["currentIndex"] == selected_index
assert 0 < returned["viewportHeight"] <= 210

if selected_index > 0:
    get("/previous")
    time.sleep(0.15)
    previous = state()
    assert previous["currentIndex"] == selected_index - 1

get("/toggle-expanded")
time.sleep(0.15)
history = state()
assert history["uiStyle"] == "expanded-card-feed", history["uiStyle"]
assert history["compactMode"] is False
assert history["historyFilter"] == "all"
assert history["closeControlVisible"] is True

get("/filter/violations")
time.sleep(0.15)
violations = state()
assert violations["historyFilter"] == "violations"
assert violations["violationsVisible"] is True
if violations["violationCount"] == 0:
    assert violations["violationEmptyStateVisible"] is True

get("/check-rules")
time.sleep(0.15)
assert state()["checkRulesEditorVisible"] is True
get("/check-rules/close")
time.sleep(0.15)
assert state()["checkRulesEditorVisible"] is False

png = get("/screenshot")
assert png.startswith(b"\x89PNG\r\n\x1a\n") and len(png) > 1_000

get("/close")
time.sleep(0.15)
closed = state()
assert closed["uiStyle"] == "single-line-ticker"
assert closed["tickerSettingsControlVisible"] is True
assert closed["windowWidth"] == closed["contentViewWidth"] == 510
assert closed["tickerPrimaryActions"] == [
    "Edit check prompt", "Display settings",
    "Open message navigation", "Hide Thinkpeek",
]

records = [json.loads(line) for line in LOG.read_text().splitlines() if line.strip()]
allowed = {
    "api_started": {"event", "timestamp", "port"},
    "command": {"event", "timestamp", "command", "origin"},
}
for record in records:
    assert record["event"] in allowed, record
    assert set(record) <= allowed[record["event"]], record

http_commands = [
    record["command"] for record in records
    if record["event"] == "command" and record["origin"] == "http"
]
for expected in ["controls", "message", "previous", "show-history",
                 "filter/violations", "check-rules", "check-rules/close", "close"]:
    if expected == "previous" and selected_index == 0:
        continue
    assert expected in http_commands, (expected, http_commands)

print(json.dumps({
    "controlsHeight": controls["windowHeight"],
    "controlsViewport": controls["viewportHeight"],
    "readerHeight": reader["windowHeight"],
    "selectedIndexPreserved": returned["currentIndex"] == selected_index,
    "expandedHistory": history["uiStyle"] == "expanded-card-feed",
    "violationEmptyState": violations["violationEmptyStateVisible"],
    "checkPromptAPI": True,
    "tickerContentWidthMatched": closed["windowWidth"] == closed["contentViewWidth"],
    "screenshotBytes": len(png),
    "loggedHTTPCommands": http_commands,
    "logContainsOnlyMetadata": True,
}, sort_keys=True))
