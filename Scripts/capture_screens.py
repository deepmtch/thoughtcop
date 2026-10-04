#!/usr/bin/env python3
"""Capture every Thinkpeek screen with realistic data, for visual review.

Run in the Parallels guest only (never on the host; see AGENTS.md lessons):
    python3 Scripts/capture_screens.py OUT_DIR
Writes OUT_DIR/NN-name.png for every dialog and state, plus manifest.json
with the window size of each capture, and fails if a detail view is not the
fixed detail width. Menus need real clicks and are captured separately with
host-side `prlctl capture`.

Test data is deliberately realistic: long session titles, five sessions
including a sub-agent, sessions working without any readable message, long
quotes and reasons, new and reviewed violations.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

API_TOKEN = "capture-screens-token-0000000000000000000"
DETAIL_WIDTH = 380
TICKER_HEIGHT = 70
DETAIL_STATES = {"reader", "history"}

SESSIONS = {
    "11111111-1111-4111-8111-111111111111": "research grants for the guidelet open-source launch",
    "22222222-2222-4222-8222-222222222222": "Clipboard image generation shortcut",
    "33333333-3333-4333-8333-333333333333": "Codex/ChatGPT configuration storage",
    "44444444-4444-4444-8444-444444444444": "EU brand finder app mockup",
    "55555555-5555-4555-8555-555555555555": "video recap",
}

def iso(delta: timedelta) -> str:
    return (datetime.now(timezone.utc) - delta).isoformat(timespec="milliseconds") \
        .replace("+00:00", "Z")


# Ages relative to launch: two from yesterday (Archive), one 25 minutes old
# (Violations), and one that turns one hour old about 90 s after launch, so it
# moves to Archive while history is open.
BOUNDARY_SECONDS = 90
VIOLATIONS = [
    {"id": "00000000-0000-4000-8000-000000000001", "timestamp": iso(timedelta(days=1, minutes=1)),
     "source": "Claude · video recap",
     "content": "Manual dubs need `dubbing_studio=true`. Adding it and retrying:",
     "reason": "The assistant adds a missing parameter on its own instead of asking the user.",
     "evidence": "Manual dubs need `dubbing_studio=true`. Adding it and retrying:",
     "provider": "Groq · qwen/qwen3.8-27b · confirmed by second check", "latencyMs": 1246,
     "checkPrompt": "The ai is taking a shortcut or workaround witouth asking th euser",
     "reviewedAt": iso(timedelta(days=1))},
    {"id": "00000000-0000-4000-8000-000000000002", "timestamp": iso(timedelta(days=1)),
     "source": "Claude · EU brand finder app mockup",
     "content": "The screens are there, but the AI parts are fake: match scores come from "
                "simple word matching, and the brief is built from the real data.",
     "reason": "The AI features are simulated with word matching without the user's consent.",
     "evidence": "The screens are there, but the AI parts are fake: match scores come from "
                 "simple word matching, and the brief is built from the real data.",
     "provider": "Groq · qwen/qwen3.8-27b", "latencyMs": 559, "checkPrompt": "rule"},
    {"id": "00000000-0000-4000-8000-000000000003",
     "timestamp": iso(timedelta(hours=1) - timedelta(seconds=BOUNDARY_SECONDS)),
     "source": "Claude · Clipboard image generation shortcut",
     "content": "The clipboard test kept failing on CI, so I marked it as skipped to get "
                "the build green.",
     "reason": "The assistant disabled a failing test instead of fixing it or asking.",
     "evidence": "I marked it as skipped to get the build green.",
     "provider": "Groq · qwen/qwen3.8-27b", "latencyMs": 812, "checkPrompt": "rule"},
    {"id": "00000000-0000-4000-8000-000000000004", "timestamp": iso(timedelta(minutes=25)),
     "source": "Claude · research grants for the guidelet open-source launch",
     "content": "The NLnet portal was down, so I assumed we meet the eligibility rules and "
                "drafted the application anyway.",
     "reason": "The assistant assumed eligibility instead of checking or asking the user.",
     "evidence": "I assumed we meet the eligibility rules and drafted the application anyway.",
     "provider": "Groq · qwen/qwen3.8-27b", "latencyMs": 690, "checkPrompt": "rule"},
]


class Checker(BaseHTTPRequestHandler):
    """Loopback checker: 'hardcoded' is a violation (confirmed), else clean."""

    def do_POST(self) -> None:  # noqa: N802
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        envelope = json.loads(body["messages"][1]["content"])
        text = envelope["EVIDENCE_RECORD"]["content"]
        if "CLAIM" in envelope:
            answer = {"confirmed": True, "reason": "The quote is in the record."}
        elif "hardcoded" in text:
            answer = {"alert": True,
                      "reason": "The assistant replaced live data with hardcoded numbers "
                                "without asking the user.",
                      "evidence": "I hardcoded last month's numbers into the dashboard instead."}
        else:
            answer = {"alert": False, "reason": "No match", "evidence": ""}
        data = json.dumps({"choices": [{"message": {"content": json.dumps(answer)}}],
                           "usage": {"prompt_tokens": 280, "completion_tokens": 70}}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_args: object) -> None:
        pass


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def request(port: int, method: str, path: str) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=15) as connection:
        connection.sendall(
            f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            f"Authorization: Bearer {API_TOKEN}\r\nContent-Length: 0\r\n"
            "Connection: close\r\n\r\n".encode("ascii"))
        chunks = []
        while chunk := connection.recv(65_536):
            chunks.append(chunk)
    return b"".join(chunks).partition(b"\r\n\r\n")[2]


def ui(port: int) -> dict:
    return json.loads(request(port, "GET", "/ui"))


def wait_ui(port: int, predicate, limit: float = 15) -> dict:
    deadline = time.monotonic() + limit
    state: dict = {}
    while time.monotonic() < deadline:
        try:
            state = ui(port)
            if predicate(state):
                return state
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"timed out; uiStyle={state.get('uiStyle')}")


def stamp(offset: float = 0) -> str:
    return (datetime.now(timezone.utc) + timedelta(seconds=offset)) \
        .isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record) + "\n")


def think(path: Path, text: str) -> None:
    write(path, {"type": "assistant", "timestamp": stamp(),
                 "message": {"content": [{"type": "thinking", "thinking": text,
                                          "signature": "s"}]}})


def reply(path: Path, text: str) -> None:
    write(path, {"type": "assistant", "timestamp": stamp(),
                 "message": {"content": [{"type": "text", "text": text}]}})


def start_working(path: Path) -> None:
    write(path, {"type": "queue-operation", "operation": "dequeue", "timestamp": stamp()})


def finish(path: Path) -> None:
    write(path, {"type": "system", "subtype": "turn_duration", "durationMs": 900,
                 "timestamp": stamp()})


class Capture:
    def __init__(self, out: Path, port: int):
        self.out, self.port, self.manifest = out, port, []

    def shot(self, name: str, kind: str, settle: float = 0.7) -> dict:
        time.sleep(settle)
        state = ui(self.port)
        path = "/screenshot/bubble" if kind == "bubble" else "/screenshot"
        (self.out / f"{name}.png").write_bytes(request(self.port, "GET", path))
        entry = {"name": name, "kind": kind, "uiStyle": state.get("uiStyle"),
                 "windowWidth": state.get("windowWidth"),
                 "windowHeight": state.get("windowHeight"),
                 "contentViewHeight": state.get("contentViewHeight"),
                 "readerTabs": state.get("readerTabs"),
                 "readerSelectedTab": state.get("readerSelectedTab"),
                 "readerText": state.get("messageReaderRenderedText"),
                 "readerTabFrames": state.get("readerTabFrames"),
                 "readerTabAreaWidth": state.get("readerTabAreaWidth"),
                 "bubbleFrame": state.get("violationBubbleFrame"),
                 "bubblePlacement": state.get("violationBubblePlacement"),
                 "bubbleOnScreen": state.get("violationBubbleOnScreen"),
                 "statusItemWindowFrame": state.get("statusItemWindowFrame"),
                 "historyFilter": state.get("historyFilter"),
                 "visibleCardCount": state.get("visibleCardCount"),
                 "violationTabCounts": state.get("violationTabCounts"),
                 "emptyStateVisible": state.get("violationEmptyStateVisible"),
                 "settingsTab": state.get("settingsTab"),
                 "tickerToolbarTrailingGap": state.get("tickerToolbarTrailingGap")}
        self.manifest.append(entry)
        return entry


def launch(root: Path, port: int, checker: int | None, violations: list) -> subprocess.Popen:
    project = root / "claude" / "project"
    project.mkdir(parents=True, exist_ok=True)
    desktop = root / "desktop" / "account"
    desktop.mkdir(parents=True, exist_ok=True)
    for session_id, title in SESSIONS.items():
        (project / f"{session_id}.jsonl").touch()
        (desktop / f"local_{session_id[:4]}.json").write_text(
            json.dumps({"cliSessionId": session_id, "title": title}))
    subagents = project / "33333333-3333-4333-8333-333333333333" / "subagents"
    subagents.mkdir(parents=True, exist_ok=True)
    (subagents / "agent-a3ae426c.jsonl").touch()
    (root / "violations.json").write_text(json.dumps(violations))
    for name in ["codex", "cache"]:
        (root / name).mkdir(exist_ok=True)
    (root / "codex-index.jsonl").write_text("")
    environment = os.environ.copy()
    environment.update({
        "THINKPEEK_API_PORT": str(port),
        "THINKPEEK_CLAUDE_PROJECTS": str(root / "claude"),
        "THINKPEEK_CODEX_SESSIONS": str(root / "codex"),
        "THINKPEEK_CODEX_INDEX": str(root / "codex-index.jsonl"),
        "THINKPEEK_CLAUDE_DESKTOP_SESSIONS": str(root / "desktop"),
        "THINKPEEK_CLAUDE_CACHE": str(root / "cache"),
        "THINKPEEK_CLAUDE_DESKTOP_CACHE": str(root / "cache"),
        "THINKPEEK_PRIVACY_AUDIT_PATH": str(root / "audit.jsonl"),
        "THINKPEEK_VIOLATIONS_PATH": str(root / "violations.json"),
        "THINKPEEK_UI_API_LOG": str(root / "ui-api.jsonl"),
        "THINKPEEK_UI_API_TOKEN": API_TOKEN,
        "THINKPEEK_HISTORY_COUNT": "0",
        "THINKPEEK_USAGE_PATH": str(root / "usage.json"),
        # The real flash and bubble durations, so each step can be captured.
        "THINKPEEK_E2E_ALERT_SECONDS": os.environ.get("THINKPEEK_CAPTURE_ALERT_SECONDS",
                                                     "3,5"),
    })
    args = ["./.build/thinkpeek", "--isolated-e2e"]
    args += (["--dummy-checker-url", f"http://127.0.0.1:{checker}/v1/chat/completions"]
             if checker else ["--local-only"])
    process = subprocess.Popen(args, env=environment, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    wait_ui(port, lambda state: state.get("initialScanComplete") is True, 20)
    return process


def stop(process: subprocess.Popen, port: int) -> None:
    try:
        request(port, "POST", "/quit")
    except OSError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    server = ThreadingHTTPServer(("127.0.0.1", free_port()), Checker)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for key in ["violationAlertsEnabled", "violationFlashEnabled", "compactWindowWidth"]:
        subprocess.run(["/usr/bin/defaults", "delete", "thinkpeek", key], capture_output=True)

    with tempfile.TemporaryDirectory(prefix="thinkpeek-capture-") as temp:
        root = Path(temp)
        port = free_port()
        process = launch(root, port, server.server_address[1], VIOLATIONS)
        capture = Capture(out, port)
        project = root / "claude" / "project"
        files = {sid: project / f"{sid}.jsonl" for sid in SESSIONS}
        grants, clipboard, codex, brand, recap = files.values()
        agent = project / "33333333-3333-4333-8333-333333333333" / "subagents" / "agent-a3ae426c.jsonl"
        try:
            time.sleep(1.5)
            think(recap, "Checking the ElevenLabs dubbing parameters before retrying the render.")
            think(brand, "The brand matcher needs the EU trademark list; reading the CSV loader.")
            think(codex, "Looking for where Codex stores its configuration and model profiles.")
            think(agent, "Sub-agent: listing ~/.codex/config.toml keys and their defaults.")
            # Files are read in no fixed order: wait for all four, then write
            # the last one so the ticker shows a known message.
            wait_ui(port, lambda s: all(marker in json.dumps(s.get("events", []))
                                        for marker in ["ElevenLabs", "trademark",
                                                       "model profiles", "Sub-agent"]))
            think(grants, "I'll compare the NLnet and Prototype Fund deadlines and their "
                          "eligibility rules for open-source developer tools.")
            wait_ui(port, lambda s: "NLnet" in s.get("peekText", ""))
            capture.shot("01-ticker", "ticker")
            request(port, "POST", "/width/narrow")
            capture.shot("02-ticker-narrow", "ticker")
            request(port, "POST", "/width/standard")

            # Two chats working, neither has written a readable message yet.
            start_working(clipboard)
            start_working(codex)
            wait_ui(port, lambda s: len(s.get("activeSources", [])) == 2)
            capture.shot("03-ticker-two-working", "ticker")
            request(port, "POST", "/message")
            wait_ui(port, lambda s: s.get("messageMode") is True)
            entry = capture.shot("04-reader-two-working", "reader")
            assert not any("active" in tab for tab in entry["readerTabs"] or []), entry
            request(port, "POST", "/close")
            finish(clipboard)
            finish(codex)
            time.sleep(0.6)

            state = ui(port)
            assert state["tickerToolbarActions"] == ["Open history", "Settings",
                                                     "Hide Thinkpeek"], state
            request(port, "POST", "/message")
            wait_ui(port, lambda s: s.get("messageMode") is True)
            capture.shot("06-reader-live-tabs", "reader")
            think(grants, "Prototype Fund requires a German residence; NLnet accepts EU applicants.")
            think(brand, "Matching works on exact names only; fuzzy matching would need approval.")
            time.sleep(1.0)
            request(port, "POST", "/previous")
            wait_ui(port, lambda s: s.get("readerLive") is False)
            capture.shot("07-reader-paused-tabs", "reader")
            request(port, "POST", "/close")
            # The user's sequence: the ticker right after closing a reader
            # with tabs (hidden tab rows once made it lay out 82 points tall).
            capture.shot("07b-ticker-after-reader", "ticker")

            request(port, "POST", "/violation-bubble/on")  # flash is on by default
            reply(brand, "The sales API returned 403, so I hardcoded last month's numbers "
                         "into the dashboard instead.")
            flashing = wait_ui(port, lambda s: s.get("statusItemFlashActive") is True)
            assert flashing["statusItemTitleIsRed"] is True, flashing
            assert flashing["violationBubbleVisible"] is False, flashing
            wait_ui(port, lambda s: s.get("violationBubbleVisible") is True, 6)
            # The real menu bar is captured from the host (it cannot be
            # rendered from inside the app); see BUG-094.
            entry = capture.shot("08-violation-bubble", "bubble", settle=0.2)
            assert entry["bubbleFrame"]["width"] == 300, entry
            assert ui(port)["violationBubbleTitle"] == "Violation · EU brand finder app mockup"
            # The quote is longer than one line, so the bubble shows two
            # (a one-line bubble is about 68 points tall).
            assert entry["bubbleFrame"]["height"] >= 80, entry
            request(port, "POST", "/violation-bubble/off")
            wait_ui(port, lambda s: s.get("violationBubbleVisible") is False)

            request(port, "POST", "/filter/all")
            wait_ui(port, lambda s: s.get("compactMode") is False)
            capture.shot("09-history-all", "history")
            request(port, "POST", "/filter/violations")
            entry = capture.shot("10-history-violations", "history")
            # Last hour: the live one, the 25-minute one, and the one about to
            # turn one hour old; yesterday's two are in Archive.
            assert entry["violationTabCounts"]["recent"] == 3, entry
            assert entry["visibleCardCount"] == 3, entry
            request(port, "POST", "/filter/archive")
            entry = capture.shot("10b-history-archive", "history")
            assert entry["historyFilter"] == "archive", entry
            assert entry["visibleCardCount"] == 2, entry
            request(port, "POST", "/filter/violations")
            moved = wait_ui(port, lambda s: s["violationTabCounts"]["archived"] == 3,
                            BOUNDARY_SECONDS + 15)
            assert moved["visibleCardCount"] == 2, moved
            assert moved["historyFilter"] == "violations", moved
            request(port, "POST", "/toggle-selected-violation")
            capture.shot("11-violation-expanded", "history")
            request(port, "POST", "/message")
            capture.shot("12-reader-violation", "reader")
            request(port, "POST", "/close")
            time.sleep(0.4)
            request(port, "POST", "/last-violation")
            wait_ui(port, lambda s: s.get("messageMode") is True)
            entry = capture.shot("12b-reader-last-violation", "reader")
            assert "hardcoded" in (entry["readerText"] or ""), entry
            request(port, "POST", "/close")
            time.sleep(0.4)
            for index, tab in enumerate(["general", "alerts", "rules", "keys"]):
                request(port, "POST", f"/settings/{tab}")
                entry = capture.shot(f"13{'abcd'[index]}-settings-{tab}", "settings", settle=1.0)
                assert entry["settingsTab"] == tab, entry
                assert ui(port)["settingsWindowTitle"] == tab.capitalize(), ui(port)["settingsWindowTitle"]
            state = ui(port)
            items = state["statusMenuItems"]
            assert items[0] == "Show Thinkpeek" and \
                items[1].startswith("Open Violation History") and \
                items[2:] == ["Show Last Violation", state["usageMenuTitle"], "Settings…",
                              "Quit Thinkpeek"], items
            assert state["settingsFlashSwitchOn"] is True, state  # default on
            assert state["settingsBubbleSwitchOn"] is False, state  # off again
            assert state["settingsHistoryChoice"] == "50 newest", state
            request(port, "POST", "/settings/close")
            wait_ui(port, lambda s: s.get("settingsVisible") is False)
            time.sleep(0.4)
            request(port, "POST", "/usage")
            capture.shot("15-usage", "editor", settle=1.0)
            request(port, "POST", "/usage/close")
        finally:
            stop(process, port)

    # Active chats but no violations: "No violations yet." must stay on
    # screen when the next thought arrives (it is not a live view).
    with tempfile.TemporaryDirectory(prefix="thinkpeek-capture-chats-") as temp:
        root = Path(temp)
        port = free_port()
        process = launch(root, port, None, [])
        capture_chats = Capture(out, port)
        project = root / "claude" / "project"
        grants = project / "11111111-1111-4111-8111-111111111111.jsonl"
        brand = project / "44444444-4444-4444-8444-444444444444.jsonl"
        try:
            time.sleep(1.5)
            think(grants, "I'll compare the NLnet and Prototype Fund deadlines.")
            wait_ui(port, lambda s: "NLnet" in json.dumps(s.get("events", [])))
            request(port, "POST", "/last-violation")
            wait_ui(port, lambda s: s.get("messageMode") is True)
            think(brand, "The brand matcher needs the EU trademark list.")
            wait_ui(port, lambda s: "trademark" in json.dumps(s.get("events", [])))
            entry = capture_chats.shot("17b-reader-no-violations-with-chats", "reader")
            assert "No violations yet." in (entry["readerText"] or ""), entry
            assert not entry["readerTabs"], entry
        finally:
            stop(process, port)

    with tempfile.TemporaryDirectory(prefix="thinkpeek-capture-empty-") as temp:
        root = Path(temp)
        port = free_port()
        process = launch(root, port, None, [])
        capture_empty = Capture(out, port)
        try:
            request(port, "POST", "/violations")
            wait_ui(port, lambda s: s.get("compactMode") is False)
            entry = capture_empty.shot("16-violations-empty", "history")
            assert entry["emptyStateVisible"] is True, entry
            request(port, "POST", "/filter/archive")
            entry = capture_empty.shot("16b-archive-empty", "history")
            assert entry["emptyStateVisible"] is True, entry
            request(port, "POST", "/close")
            time.sleep(0.4)
            request(port, "POST", "/last-violation")
            wait_ui(port, lambda s: s.get("messageMode") is True)
            entry = capture_empty.shot("17-reader-no-violations", "reader")
            assert "No violations yet." in (entry["readerText"] or ""), entry
            # No chat yet: no lone "All" chip and no Live line.
            assert not entry["readerTabs"], entry
        finally:
            stop(process, port)
    server.shutdown()
    for key in ["violationAlertsEnabled", "violationFlashEnabled"]:
        subprocess.run(["/usr/bin/defaults", "delete", "thinkpeek", key],
                   capture_output=True)

    manifest = capture.manifest + capture_chats.manifest + capture_empty.manifest
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    wrong = [m for m in manifest
             if m["kind"] in DETAIL_STATES and m["windowWidth"] != DETAIL_WIDTH]
    for entry in manifest:
        if entry["kind"] == "bubble":
            assert entry["bubbleOnScreen"] is True, f"{entry['name']}: bubble off-screen: {entry}"
            if entry["bubblePlacement"] == "under-icon":
                frame, anchor = entry["bubbleFrame"], entry["statusItemWindowFrame"]
                assert frame["y"] + frame["height"] <= anchor["y"], \
                    f"{entry['name']}: bubble is not below the menu-bar icon: {frame} {anchor}"
            continue
        if entry["kind"] == "ticker":
            # Hide (✕) sits at the right edge, 10 pt in (BUG-096 follow-up).
            assert entry["tickerToolbarTrailingGap"] <= 12, \
                f"{entry['name']}: gap right of the toolbar: {entry['tickerToolbarTrailingGap']} pt"
            assert entry["windowHeight"] == TICKER_HEIGHT, \
                f"{entry['name']}: ticker is {entry['windowHeight']} pt tall, not {TICKER_HEIGHT}"
        if entry["kind"] not in {"editor", "settings"}:
            assert entry["contentViewHeight"] == entry["windowHeight"], \
                f"{entry['name']}: content {entry['contentViewHeight']} pt tall in a " \
                f"{entry['windowHeight']} pt window (top is cut off)"
        tabs = entry["readerTabs"] or []
        frames = entry.get("readerTabFrames") or []
        area = entry.get("readerTabAreaWidth") or 0
        for frame in frames:
            assert frame["x"] + frame["width"] <= area, \
                f"{entry['name']}: tab chip runs past the reader: {frame} > {area}"
            assert frame["width"] <= (area - 6) // 2 + 1, \
                f"{entry['name']}: tab chip wider than half the row: {frame}"
            # Dot and title keep 10 pt to each chip edge (BUG-093).
            assert frame["contentX"] >= 10 and \
                frame["contentX"] + frame["contentWidth"] <= frame["width"] - 10, \
                f"{entry['name']}: tab chip text touches its edge: {frame}"
        for a_, b_ in zip(frames, frames[1:]):
            if a_["y"] == b_["y"]:
                assert a_["x"] + a_["width"] < b_["x"], \
                    f"{entry['name']}: tab chips overlap: {a_} {b_}"
        assert len(tabs) <= 4, f"{entry['name']}: more than 3 chat tabs + All: {tabs}"
        assert not any(" · agent " in tab or "active" in tab for tab in tabs), \
            f"{entry['name']}: sub-agent or aggregate tab: {tabs}"
        assert "**" not in (entry.get("readerText") or ""), \
            f"{entry['name']}: markdown markers visible in the rendered reader"
    for entry in manifest:
        print(f"{entry['name']:28} {entry['kind']:9} {entry['windowWidth']}x{entry['windowHeight']}"
              f"  tabs={entry['readerTabs'] or ''}")
    assert not wrong, f"detail views not {DETAIL_WIDTH} points wide: {wrong}"
    print(f"captured {len(manifest)} screens; every detail view is {DETAIL_WIDTH} points wide")


if __name__ == "__main__":
    main()
