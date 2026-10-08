#!/usr/bin/env python3
"""Exercise the running AppKit UI only through Thoughtcrime's local API."""

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path


BASE = os.environ.get("THOUGHTCRIME_UI_API", "http://127.0.0.1:17321")
LOG = Path(os.environ.get(
    "THOUGHTCRIME_UI_API_LOG",
    Path.home() / "Library/Logs/Thoughtcrime/ui-api.jsonl",
))
TOKEN_PATH = Path(os.environ.get(
    "THOUGHTCRIME_UI_API_TOKEN_PATH",
    Path.home() / "Library/Application Support/Thoughtcrime/ui-api-token",
))
TOKEN = os.environ.get("THOUGHTCRIME_UI_API_TOKEN") or TOKEN_PATH.read_text().strip()


def request(path: str, method: str = "GET", authenticated: bool = True) -> bytes:
    headers = {"Authorization": f"Bearer {TOKEN}"} if authenticated else {}
    value = urllib.request.Request(BASE + path, headers=headers, method=method)
    with urllib.request.urlopen(value, timeout=5) as response:
        if response.status != 200:
            raise AssertionError(f"{path}: HTTP {response.status}")
        return response.read()


def post(path: str) -> bytes:
    return request(path, method="POST")


def state() -> dict:
    return json.loads(request("/ui"))


def wait_state(predicate, timeout: float = 3.0) -> dict:
    deadline = time.monotonic() + timeout
    latest = {}
    while time.monotonic() < deadline:
        latest = state()
        if predicate(latest):
            return latest
        time.sleep(0.05)
    raise AssertionError(f"UI state transition timed out: {latest}")


try:
    request("/ui", authenticated=False)
except urllib.error.HTTPError as error:
    assert error.code == 401, error.code
else:
    raise AssertionError("unauthenticated UI state request succeeded")

try:
    request("/close")
except urllib.error.HTTPError as error:
    assert error.code == 405, error.code
else:
    raise AssertionError("state-changing GET request succeeded")


deadline = time.monotonic() + 15
while time.monotonic() < deadline:
    if state().get("initialScanComplete") is True:
        break
    time.sleep(0.1)
else:
    raise AssertionError("initial transcript scan did not complete")

post("/message")
reader = wait_state(lambda value: value.get("uiStyle") == "full-message")
assert reader["uiStyle"] == "full-message", reader["uiStyle"]
assert reader["messageMode"] is True
assert 118 <= reader["windowHeight"] <= 420, reader["windowHeight"]
assert reader["closeControlVisible"] is True
assert reader["quitControlVisible"] is False
assert reader["quitControlInOverflow"] is False

post("/toggle-expanded")
history = wait_state(lambda value: value.get("uiStyle") == "expanded-card-feed")
assert history["uiStyle"] == "expanded-card-feed", history["uiStyle"]
assert history["compactMode"] is False
assert history["historyFilter"] == "all"
assert history["closeControlVisible"] is True
assert history["detailCheckRulesControlVisible"] is False
assert history["detailSettingsControlVisible"] is False
assert history["latestControlVisible"] is False  # newest first: only with unseen items

post("/filter/violations")
violations = wait_state(lambda value:
                        value.get("historyFilter") == "violations" and
                        value.get("violationsVisible") is True)
assert violations["historyFilter"] == "violations"
assert violations["violationsVisible"] is True
if violations["violationTabCounts"]["recent"] == 0:
    assert violations["violationEmptyStateVisible"] is True

post("/check-rules")
wait_state(lambda value: value.get("checkRulesEditorVisible") is True)
post("/check-rules/close")
wait_state(lambda value: value.get("checkRulesEditorVisible") is False)

png = request("/screenshot")
assert png.startswith(b"\x89PNG\r\n\x1a\n") and len(png) > 1_000

post("/close")
closed = wait_state(lambda value: value.get("uiStyle") == "single-line-ticker")
assert closed["uiStyle"] == "single-line-ticker"
assert closed["tickerSettingsControlVisible"] is True
assert closed["windowWidth"] == closed["contentViewWidth"] == 510
assert closed["tickerToolbarAttached"] is True
assert closed["tickerPrimaryActions"] == ["Open history", "Settings", "Hide Thoughtcrime"]
assert closed["tickerToolbarActions"] == closed["tickerPrimaryActions"]

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
for expected in ["message", "show-history",
                 "filter/violations", "check-rules", "check-rules/close", "close"]:
    assert expected in http_commands, (expected, http_commands)

print(json.dumps({
    "readerHeight": reader["windowHeight"],
    "selectedIndexPreserved": returned["currentIndex"] == reader_index,
    "expandedHistory": history["uiStyle"] == "expanded-card-feed",
    "violationEmptyState": violations["violationEmptyStateVisible"],
    "checkPromptAPI": True,
    "tickerContentWidthMatched": closed["windowWidth"] == closed["contentViewWidth"],
    "screenshotBytes": len(png),
    "loggedHTTPCommands": http_commands,
    "unauthenticatedStateRejected": True,
    "mutatingGETRejected": True,
    "logContainsOnlyMetadata": True,
}, sort_keys=True))
