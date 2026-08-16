#!/usr/bin/env python3
"""Black-box multi-session test with a deterministic local checker."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class DummyChecker(BaseHTTPRequestHandler):
    requests: list[str] = []
    lock = threading.Lock()

    def do_POST(self) -> None:  # noqa: N802
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size))
        envelope = json.loads(payload["messages"][1]["content"])
        content = envelope["EVIDENCE_RECORD"]["content"]
        with self.lock:
            self.requests.append(content)

        if "CLAUDE_ALERT" in content:
            time.sleep(0.9)  # finish after Codex to exercise out-of-order results
            decision = {
                "alert": True,
                "reason": "Dummy detected explicit Claude uncertainty",
                "evidence": "CLAUDE_ALERT",
            }
        elif "CODEX_CLEAN" in content:
            time.sleep(0.25)
            decision = {"alert": False, "reason": "No match", "evidence": ""}
        else:
            self.send_error(500, "unexpected evidence")
            return

        response = {
            "choices": [{"message": {"content": json.dumps(decision)}}]
        }
        data = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, _format: str, *_args: object) -> None:
        pass


def get_json(base: str, path: str = "/ui") -> dict:
    with urllib.request.urlopen(base + path, timeout=3) as response:
        return json.loads(response.read())


def wait_for(predicate, timeout: float = 12.0) -> dict:
    deadline = time.monotonic() + timeout
    latest: dict = {}
    while time.monotonic() < deadline:
        try:
            latest = get_json(API_BASE)
            if predicate(latest):
                return latest
        except Exception:
            pass
        time.sleep(0.05)
    raise AssertionError(f"condition timed out; last state={latest}")


def append(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, separators=(",", ":")) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


ui_port = free_port()
checker_port = free_port()
API_BASE = f"http://127.0.0.1:{ui_port}"

server = ThreadingHTTPServer(("127.0.0.1", checker_port), DummyChecker)
server_thread = threading.Thread(target=server.serve_forever, daemon=True)
server_thread.start()

with tempfile.TemporaryDirectory(prefix="thinkpeek-e2e-") as temporary:
    root = Path(temporary)
    claude_root = root / "claude"
    codex_root = root / "codex"
    claude_path = claude_root / "project" / "11111111-1111-4111-8111-111111111111.jsonl"
    codex_path = (
        codex_root / "2026" / "08" / "16" /
        "rollout-2026-08-16T00-00-00-22222222-2222-4222-8222-222222222222.jsonl"
    )
    claude_path.parent.mkdir(parents=True)
    codex_path.parent.mkdir(parents=True)
    claude_path.touch()
    codex_path.touch()

    audit_path = root / "privacy-audit.jsonl"
    ui_log_path = root / "ui-api.jsonl"
    environment = os.environ.copy()
    environment.update({
        "THINKPEEK_API_PORT": str(ui_port),
        "THINKPEEK_CLAUDE_PROJECTS": str(claude_root),
        "THINKPEEK_CODEX_SESSIONS": str(codex_root),
        "THINKPEEK_CODEX_INDEX": str(root / "codex-index.jsonl"),
        "THINKPEEK_PRIVACY_AUDIT_PATH": str(audit_path),
        "THINKPEEK_UI_API_LOG": str(ui_log_path),
        "THINKPEEK_HISTORY_COUNT": "0",
    })
    process = subprocess.Popen(
        ["./.build/thinkpeek", "--isolated-e2e", "--dummy-checker-url",
         f"http://127.0.0.1:{checker_port}/v1/chat/completions"],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        initial = wait_for(lambda state: state.get("initialScanComplete") is True)
        assert initial["externalAnalysisEnabled"] is True, initial
        assert initial["analysisDestination"] == "Dummy · deterministic-checker", initial

        append(claude_path, {
            "timestamp": "2026-08-16T10:00:00.000Z",
            "type": "assistant",
            "message": {"content": [{
                "type": "thinking",
                "thinking": "CLAUDE_ALERT: I am unsure and may improvise.",
                "signature": "sealed",
            }]},
        })
        append(codex_path, {
            "timestamp": "2026-08-16T10:00:00.050Z",
            "type": "response_item",
            "payload": {"type": "custom_tool_call", "name": "exec",
                        "input": "TOOL_SECRET_MUST_NOT_REACH_CHECKER"},
        })
        append(codex_path, {
            "timestamp": "2026-08-16T10:00:00.100Z",
            "type": "response_item",
            "payload": {"type": "reasoning", "summary": [{
                "type": "summary_text", "text": "ENCRYPTED_PLACEHOLDER_MUST_NOT_RENDER"
            }], "encrypted_content": "sealed"},
        })
        append(codex_path, {
            "timestamp": "2026-08-16T10:00:00.200Z",
            "type": "response_item",
            "payload": {"type": "reasoning", "content": [{
                "type": "reasoning_text",
                "text": "CODEX_CLEAN: I have a clear deterministic plan."
            }], "encrypted_content": "sealed"},
        })

        in_flight = wait_for(lambda state: state.get("checkerRequestInFlight") is True)
        assert in_flight["checkerActivityIndicatorVisible"] is True, in_flight
        assert in_flight["checkerActivityDestination"] == \
            "Dummy · deterministic-checker", in_flight

        finished = wait_for(lambda state: {
            event.get("kind") for event in state.get("events", [])
        } >= {"drift-alert", "drift-clean"} and
            state.get("checkerRequestInFlight") is False)

        with DummyChecker.lock:
            sent = list(DummyChecker.requests)
        assert sorted(sent) == sorted([
            "CLAUDE_ALERT: I am unsure and may improvise.",
            "CODEX_CLEAN: I have a clear deterministic plan.",
        ]), sent
        assert all("TOOL_SECRET" not in text for text in sent), sent
        assert all("ENCRYPTED_PLACEHOLDER" not in text for text in sent), sent
        assert finished["navigableCount"] == 2, finished
        assert "CODEX_CLEAN" in finished["peekText"], finished
        assert "unavailable" not in finished["peekText"].lower(), finished
        assert finished["tickerAlarmActive"] is False, finished

        get_json(API_BASE, "/previous")
        previous = wait_for(lambda state: state.get("currentIndex") == 0)
        assert previous["tickerAlarmActive"] is True, previous
        assert previous["peekSource"] == "Thinkpeek · Warning", previous
        assert "Dummy detected explicit Claude uncertainty" in previous["peekText"], previous

        get_json(API_BASE, "/next")
        latest = wait_for(lambda state: state.get("currentIndex") == 1)
        assert "CODEX_CLEAN" in latest["peekText"], latest
        assert latest["tickerAlarmActive"] is False, latest

        audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
        requests = [item for item in audit
                    if item.get("action") == "external_reasoning_request"]
        results = [item for item in audit
                   if item.get("action") == "external_reasoning_result"]
        assert len(requests) == 2, requests
        assert sorted(item["status"] for item in results) == ["alert", "clean"], results
        assert {item["request_id"] for item in requests} == \
            {item["request_id"] for item in results}, (requests, results)

        print(json.dumps({
            "concurrentProviders": ["Claude", "Codex"],
            "dummyRequests": len(sent),
            "outOfOrderResults": True,
            "alertAndClean": True,
            "encryptedAndToolsExcluded": True,
            "placeholderNeverRendered": True,
            "tickerNavigation": "alert-to-clean",
            "checkerLightObserved": True,
            "auditPairs": len(results),
        }, sort_keys=True))
    finally:
        try:
            get_json(API_BASE, "/quit")
        except Exception:
            pass
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=4)
        server.shutdown()
        server.server_close()
        if process.returncode not in (0, None):
            error = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"isolated Thinkpeek exited {process.returncode}: {error}")
