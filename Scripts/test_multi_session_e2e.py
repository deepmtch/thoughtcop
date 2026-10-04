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
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from e2e_defaults import configure_isolated_rules


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class DummyChecker(BaseHTTPRequestHandler):
    requests: list[str] = []
    verifications: list[str] = []
    lock = threading.Lock()

    def do_POST(self) -> None:  # noqa: N802
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size))
        envelope = json.loads(payload["messages"][1]["content"])
        content = envelope["EVIDENCE_RECORD"]["content"]
        if "CLAIM" in envelope:
            # Second check of a violation claim: this suite confirms every one.
            with self.lock:
                self.verifications.append(content)
            self.respond({"confirmed": True, "reason": "dummy verification"})
            return
        with self.lock:
            self.requests.append(content)

        if "ALERT" in content:
            time.sleep(0.9)  # finish after Codex to exercise out-of-order results
            decision = {
                "alert": True,
                "reason": "Dummy detected explicit Claude uncertainty",
                "evidence": "ALERT",
            }
        elif "CLEAN" in content:
            time.sleep(0.25)
            decision = {"alert": False, "reason": "No match", "evidence": ""}
        else:
            self.send_error(500, "unexpected evidence")
            return
        self.respond(decision)

    def respond(self, decision: dict) -> None:
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


API_TOKEN = "isolated-e2e-ui-token-0000000000000000"


def api_request(base: str, path: str, method: str,
                token: str | None = API_TOKEN) -> tuple[int, bytes]:
    host_port = base.removeprefix("http://")
    host, port_text = host_port.rsplit(":", 1)
    authorization = f"Authorization: Bearer {token}\r\n" if token else ""
    with socket.create_connection((host, int(port_text)), timeout=3) as connection:
        connection.sendall(
            f"{method} {path} HTTP/1.1\r\nHost: {host_port}\r\n"
            f"{authorization}Connection: close\r\n\r\n"
            .encode("ascii")
        )
        chunks: list[bytes] = []
        while True:
            chunk = connection.recv(65_536)
            if not chunk:
                break
            chunks.append(chunk)
    response = b"".join(chunks)
    header, separator, body = response.partition(b"\r\n\r\n")
    if not separator:
        raise RuntimeError(f"invalid API response: {response[:200]!r}")
    status_line = header.split(b"\r\n", 1)[0]
    status = int(status_line.split(b" ", 2)[1])
    return status, body


def get_json(base: str, path: str = "/ui") -> dict:
    method = "GET" if path in {"/ui", "/screenshot"} else "POST"
    status, body = api_request(base, path, method)
    if status != 200:
        raise RuntimeError(f"invalid API response: HTTP {status} {body[:200]!r}")
    return json.loads(body)


def wait_for(predicate, timeout: float = 12.0,
             process: subprocess.Popen | None = None,
             diagnostic_log: Path | None = None) -> dict:
    deadline = time.monotonic() + timeout
    latest: dict = {}
    last_error = ""
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            error = process.stderr.read() if process.stderr else ""
            raise AssertionError(
                f"Thinkpeek exited {process.returncode} before API readiness: {error}")
        try:
            latest = get_json(API_BASE)
            if predicate(latest):
                return latest
        except Exception as error:
            last_error = repr(error)
        time.sleep(0.05)
    diagnostic = ""
    if process is not None and process.poll() is None:
        sample = subprocess.run(
            ["/usr/bin/sample", str(process.pid), "1", "1"],
            capture_output=True, text=True, timeout=5, check=False)
        diagnostic = "\nprocess sample:\n" + sample.stdout[:4000]
        sockets = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-a", "-p", str(process.pid), "-iTCP"],
            capture_output=True, text=True, timeout=5, check=False)
        diagnostic += "\nprocess sockets:\n" + sockets.stdout
        for host in ["127.0.0.1", "[::1]"]:
            probe = subprocess.run(
                ["/usr/bin/curl", "--noproxy", "*", "-sv", "--max-time", "2",
                 "--header", f"Authorization: Bearer {API_TOKEN}",
                 f"http://{host}:{ui_port}/ui"],
                capture_output=True, text=True, timeout=4, check=False)
            diagnostic += (f"\ncurl probe {host}:\n" + probe.stderr +
                           "\n" + probe.stdout)
    if diagnostic_log is not None and diagnostic_log.exists():
        diagnostic += "\nUI API log:\n" + diagnostic_log.read_text()
    raise AssertionError(
        f"condition timed out; pid={process.pid if process else 'n/a'} "
        f"api={API_BASE} last state={latest} last error={last_error}{diagnostic}")


def append(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, separators=(",", ":")) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def write_claude_desktop_cache(path: Path, conversation: dict) -> None:
    zstd = next((candidate for candidate in [
        "/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"
    ] if Path(candidate).is_file()), None)
    if zstd is None:
        raise AssertionError("zstd is required for Claude Desktop cache tests")
    compressed = subprocess.run(
        [zstd, "--compress", "--stdout", "--quiet"],
        input=json.dumps(conversation, separators=(",", ":")).encode(),
        capture_output=True, check=True,
    ).stdout
    header = (
        "1/0/https://claude.ai/api/organizations/org-1/chat_conversations/"
        f"{conversation['uuid']}?tree=True&rendering_mode=messages\n"
    ).encode()
    path.write_bytes(header + compressed)


test_started_at = datetime.now(timezone.utc)


def record_timestamp(milliseconds: int) -> str:
    value = test_started_at + timedelta(milliseconds=milliseconds)
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


ui_port = free_port()
checker_port = free_port()
API_BASE = f"http://127.0.0.1:{ui_port}"

# This suite expects the default violation settings of the test binary.
for key in ["violationHistoryLimit", "violationVerificationEnabled",
            "violationFlashEnabled", "violationAlertsEnabled"]:
    subprocess.run(["/usr/bin/defaults", "delete", "thinkpeek", key],
                   capture_output=True, check=False)

server = ThreadingHTTPServer(("127.0.0.1", checker_port), DummyChecker)
server_thread = threading.Thread(target=server.serve_forever, daemon=True)
server_thread.start()

with tempfile.TemporaryDirectory(prefix="thinkpeek-e2e-") as temporary:
    root = Path(temporary)
    claude_root = root / "claude"
    codex_root = root / "codex"
    claude_path = claude_root / "project" / "11111111-1111-4111-8111-111111111111.jsonl"
    claude_second = claude_root / "project" / "33333333-3333-4333-8333-333333333333.jsonl"
    codex_path = (
        codex_root / "2026" / "08" / "16" /
        "rollout-2026-08-16T00-00-00-22222222-2222-4222-8222-222222222222.jsonl"
    )
    codex_second = (
        codex_root / "2026" / "08" / "16" /
        "rollout-2026-08-16T00-00-01-44444444-4444-4444-8444-444444444444.jsonl"
    )
    claude_path.parent.mkdir(parents=True)
    codex_path.parent.mkdir(parents=True)
    for transcript in [claude_path, claude_second, codex_path, codex_second]:
        transcript.touch()

    desktop_sessions = root / "claude-desktop-sessions" / "account" / "workspace"
    desktop_sessions.mkdir(parents=True)
    (desktop_sessions / "local_alpha.json").write_text(json.dumps({
        "cliSessionId": "11111111-1111-4111-8111-111111111111",
        "title": "Claude Alpha",
    }))
    (desktop_sessions / "local_beta.json").write_text(json.dumps({
        "cliSessionId": "33333333-3333-4333-8333-333333333333",
        "title": "Claude Beta",
    }))
    codex_index = root / "codex-index.jsonl"
    codex_index.write_text("\n".join([
        json.dumps({"id": "22222222-2222-4222-8222-222222222222",
                    "thread_name": "Codex Alpha"}),
        json.dumps({"id": "44444444-4444-4444-8444-444444444444",
                    "thread_name": "Codex Beta"}),
    ]) + "\n")

    audit_path = root / "privacy-audit.jsonl"
    violations_path = root / "violations.json"
    ui_log_path = root / "ui-api.jsonl"
    claude_cache = root / "claude-cache"
    claude_cache.mkdir()
    cloud_stream = claude_cache / "cloud-stream_0"
    cloud_stream.write_text(
        "1/0/https://claude.ai/v1/code/sessions/"
        "cse_0123456789/events/stream?from_sequence_num=1\n")
    environment = os.environ.copy()
    environment.update({
        "THINKPEEK_API_PORT": str(ui_port),
        "THINKPEEK_CLAUDE_PROJECTS": str(claude_root),
        "THINKPEEK_CODEX_SESSIONS": str(codex_root),
        "THINKPEEK_CODEX_INDEX": str(codex_index),
        "THINKPEEK_CLAUDE_DESKTOP_SESSIONS": str(
            root / "claude-desktop-sessions"),
        "THINKPEEK_CLAUDE_CACHE": str(claude_cache),
        "THINKPEEK_CLAUDE_DESKTOP_CACHE": str(claude_cache),
        "THINKPEEK_PRIVACY_AUDIT_PATH": str(audit_path),
        "THINKPEEK_VIOLATIONS_PATH": str(violations_path),
        "THINKPEEK_UI_API_LOG": str(ui_log_path),
        "THINKPEEK_UI_API_TOKEN": API_TOKEN,
        "THINKPEEK_HISTORY_COUNT": "0",
    })
    configure_isolated_rules()
    process = subprocess.Popen(
        ["./.build/thinkpeek", "--isolated-e2e", "--dummy-checker-url",
         f"http://127.0.0.1:{checker_port}/v1/chat/completions"],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        initial = wait_for(lambda state: state.get("initialScanComplete") is True,
                           timeout=20, process=process,
                           diagnostic_log=ui_log_path)
        # Thinkpeek checks only records written after it started, by their own
        # timestamp, so every record below is stamped after readiness.
        test_started_at = datetime.now(timezone.utc)
        assert api_request(API_BASE, "/ui", "GET", token=None)[0] == 401
        assert api_request(API_BASE, "/close", "GET")[0] == 405
        assert api_request(API_BASE, "/controls", "POST")[0] == 404
        assert api_request(API_BASE, "/ui", "POST")[0] == 405
        assert api_request(API_BASE, "/not-a-route", "GET")[0] == 404
        listener = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-a", "-p", str(process.pid),
             f"-iTCP:{ui_port}", "-sTCP:LISTEN"],
            capture_output=True, text=True, check=True,
        ).stdout
        assert "127.0.0.1:" in listener and "*:" not in listener, listener
        defaults_state = get_json(API_BASE, "/ui")
        # Defaults chosen by the user: flash on, bubble off.
        assert defaults_state["violationFlashEnabled"] is True, defaults_state
        assert defaults_state["violationBubbleEnabled"] is False, defaults_state
        # The flash is exercised below; keep the provider checks quiet.
        get_json(API_BASE, "/violation-flash/off")
        initial = wait_for(lambda state:
            state.get("violationFlashEnabled") is False)
        assert initial["externalAnalysisEnabled"] is True, initial
        assert initial["analysisDestination"] == "Dummy · deterministic-checker", initial

        with cloud_stream.open("a", encoding="utf-8") as stream:
            stream.write('data: {"event_type":"system","payload":'
                         '{"subtype":"status","status":"requesting"}}\n')
            stream.flush()
            os.fsync(stream.fileno())
        cloud_active = wait_for(lambda state:
            state.get("activeSources") == ["Claude · cloud chat 456789"])
        assert cloud_active["peekSource"] == "Claude · cloud chat 456789", cloud_active
        assert cloud_active["peekText"] == "Working…", cloud_active

        get_json(API_BASE, "/message")
        live_reader = wait_for(lambda state: state.get("messageMode") is True)
        assert live_reader["messageReaderSource"] == \
            "Claude · cloud chat 456789", live_reader
        assert live_reader["messageReaderText"].startswith("Working…"), live_reader
        get_json(API_BASE, "/close")
        collapsed = wait_for(lambda state:
            state.get("peekMode") is True and state.get("windowVisible") is True)
        assert collapsed["peekSource"] == "Claude · cloud chat 456789", collapsed
        assert collapsed["peekText"] == "Working…", collapsed

        with cloud_stream.open("a", encoding="utf-8") as stream:
            stream.write('data: {"event_type":"stream_event","payload":'
                         '{"event":{"type":"content_block_delta"}}}\n')
            stream.write('data: {"event_type":"control_request","payload":'
                         '{"request_id":"ask-1"}}\n')
            # Claude writes final stream frames after AskUserQuestion. They
            # belong to the waiting turn and must not reactivate the session.
            stream.write('data: {"event_type":"stream_event","payload":'
                         '{"event":{"type":"message_stop"}}}\n')
            stream.flush()
            os.fsync(stream.fileno())
        cloud_waiting = wait_for(lambda state:
            state.get("waitingSources") == ["Claude · cloud chat 456789"])
        assert cloud_waiting["operationPending"] is False, cloud_waiting
        assert cloud_waiting["operationWaiting"] is True, cloud_waiting
        assert cloud_waiting["peekSource"] == "Claude · cloud chat 456789", cloud_waiting
        assert cloud_waiting["peekText"] == "Waiting for you…", cloud_waiting

        with cloud_stream.open("a", encoding="utf-8") as stream:
            stream.write('data: {"event_type":"system","payload":'
                         '{"subtype":"status","status":"requesting"}}\n')
            stream.write('data: {"event_type":"result","payload":'
                         '{"is_error":false}}\n')
            stream.flush()
            os.fsync(stream.fileno())
        cloud_done = wait_for(lambda state:
            state.get("operationPending") is False)
        assert cloud_done["activeSources"] == [], cloud_done

        append(claude_path, {
            "timestamp": record_timestamp(0),
            "type": "queue-operation", "operation": "dequeue",
        })
        append(codex_path, {
            "timestamp": record_timestamp(50),
            "type": "event_msg", "payload": {"type": "task_started"},
        })
        both_active = wait_for(lambda state:
            len(state.get("activeSources", [])) == 2)
        assert both_active["operationPending"] is True, both_active
        assert both_active["activityDisplaySource"] == \
            "Claude + Codex · 2 active", both_active
        assert both_active["activityDisplayText"] == \
            "Working: Claude · Claude Alpha • Codex · Codex Alpha", both_active
        assert both_active["peekSource"] == both_active["activityDisplaySource"], both_active
        assert both_active["peekText"] == both_active["activityDisplayText"], both_active

        append(claude_path, {
            "timestamp": record_timestamp(100),
            "type": "assistant",
            "message": {"content": [{
                "type": "thinking",
                "thinking": "CLAUDE_ALERT: I am unsure and may improvise.",
                "signature": "sealed",
            }]},
        })
        append(codex_path, {
            "timestamp": record_timestamp(150),
            "type": "response_item",
            "payload": {"type": "custom_tool_call", "name": "exec",
                        "input": "TOOL_SECRET_MUST_NOT_REACH_CHECKER"},
        })
        append(codex_path, {
            "timestamp": record_timestamp(200),
            "type": "response_item",
            "payload": {"type": "reasoning", "summary": [{
                "type": "summary_text", "text": "CODEX_LOCAL_SUMMARY"
            }], "encrypted_content": "sealed"},
        })
        append(codex_path, {
            "timestamp": record_timestamp(300),
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
        assert all("CODEX_LOCAL_SUMMARY" not in text for text in sent), sent
        assert finished["navigableCount"] == 3, finished
        assert finished["violationCount"] == 1, finished
        assert finished["violationFlashEnabled"] is False, finished
        assert finished["violationBubbleEnabled"] is False, finished
        assert finished["statusItemFlashActive"] is False, finished
        assert finished["violationBubbleVisible"] is False, finished
        assert finished["menuBarViolationAlertActive"] is True, finished
        assert finished["statusItemBadgeText"] == "1", finished
        assert finished["currentViolationVisible"] is False, finished
        assert finished["tickerAlarmActive"] is False, finished
        assert finished["windowVisible"] is True, finished
        assert len(finished["violations"]) == 1, finished
        assert finished["violations"][0]["checkPrompt"], finished
        screenshot_status, screenshot = api_request(
            API_BASE, "/screenshot", "GET")
        assert screenshot_status == 200, screenshot_status
        assert screenshot.startswith(b"\x89PNG\r\n\x1a\n"), screenshot[:16]
        assert len(screenshot) > 1_000, len(screenshot)

        get_json(API_BASE, "/hide")
        hidden_alert = wait_for(lambda state: state.get("windowVisible") is False)
        assert hidden_alert["violationCount"] == 1, hidden_alert
        get_json(API_BASE, "/violations")
        violation_list = wait_for(lambda state:
            state.get("uiStyle") == "violations-list" and
            state.get("windowVisible") is True)
        assert violation_list["violationsVisible"] is True, violation_list
        assert violation_list["visibleCardCount"] == 1, violation_list
        assert violation_list["historyFilter"] == "violations", violation_list
        assert violation_list["detailCheckRulesControlVisible"] is False, violation_list
        assert violation_list["detailSettingsControlVisible"] is False, violation_list
        # Newest first: "↑ N new" appears only when unseen items are above.
        assert violation_list["latestControlVisible"] is False, violation_list
        get_json(API_BASE, "/filter/all")
        all_list = wait_for(lambda state:
            state.get("historyFilter") == "all" and
            state.get("uiStyle") == "expanded-card-feed")
        assert all_list["visibleCardCount"] == 3, all_list
        get_json(API_BASE, "/filter/violations")
        filtered_again = wait_for(lambda state:
            state.get("historyFilter") == "violations")
        assert filtered_again["visibleCardCount"] == 1, filtered_again
        get_json(API_BASE, "/close")
        resumed_after_alert = wait_for(lambda state:
            state.get("uiStyle") == "single-line-ticker")
        assert "CODEX_CLEAN" in resumed_after_alert["peekText"], resumed_after_alert
        assert resumed_after_alert["currentViolationVisible"] is False, resumed_after_alert

        append(claude_path, {
            "timestamp": record_timestamp(400),
            "type": "assistant",
            "message": {"content": [{
                "type": "text", "text": "RESPONSE_CLEAN: done"
            }]},
        })
        append(codex_path, {
            "timestamp": record_timestamp(450),
            "type": "event_msg", "payload": {"type": "task_complete"},
        })
        inactive = wait_for(lambda state:
            state.get("operationPending") is False and
            state.get("checkerRequestInFlight") is False and
            any(event.get("kind") == "drift-clean" and
                event.get("evidenceType") == "assistant_response"
                for event in state.get("events", [])))
        assert inactive["activeSources"] == [], inactive

        get_json(API_BASE, "/previous")
        local_summary = wait_for(lambda state: state.get("currentIndex") == 1)
        assert local_summary["peekText"] == "CODEX_LOCAL_SUMMARY", local_summary
        assert local_summary["peekSource"] == "Codex · Codex Alpha", local_summary
        get_json(API_BASE, "/previous")
        previous = wait_for(lambda state: state.get("currentIndex") == 0)
        assert previous["tickerAlarmActive"] is True, previous
        # Showing a violation never changes the ticker background.
        assert previous["tickerBackgroundRGBA"] == local_summary["tickerBackgroundRGBA"], previous
        assert previous["tickerBackgroundMode"] == "normal-semantic", previous
        assert previous["peekSource"] == "Claude · Claude Alpha", previous
        assert "Dummy detected explicit Claude uncertainty" in previous["peekText"], previous

        get_json(API_BASE, "/next")
        wait_for(lambda state: state.get("currentIndex") == 1)
        get_json(API_BASE, "/next")
        latest = wait_for(lambda state: state.get("currentIndex") == 2)
        assert "CODEX_CLEAN" in latest["peekText"], latest
        assert latest["peekSource"] == "Codex · Codex Alpha", latest
        assert latest["tickerAlarmActive"] is False, latest

        # Leave the carousel on an older record, then start a second Claude
        # conversation. The passive ticker must still switch to the new record.
        get_json(API_BASE, "/previous")
        wait_for(lambda state: state.get("currentIndex") == 1)
        append(claude_second, {
            "timestamp": record_timestamp(1_000),
            "type": "assistant",
            "message": {"content": [{
                "type": "thinking",
                "thinking": "CLAUDE_SECOND_CLEAN: fresh beta reasoning.",
                "signature": "sealed",
            }]},
        })
        claude_beta = wait_for(lambda state:
            "CLAUDE_SECOND_CLEAN" in state.get("peekText", "") and
            state.get("checkerRequestInFlight") is False)
        assert claude_beta["currentIndex"] == 3, claude_beta
        assert claude_beta["peekSource"] == "Claude · Claude Beta", claude_beta

        # Opening a message is the one explicit freeze state. A concurrent
        # Codex conversation may arrive and be checked, but must not replace
        # the record under the reader until Close resumes the latest ticker.
        get_json(API_BASE, "/message")
        reader = wait_for(lambda state: state.get("messageMode") is True)
        reader_text = reader["messageReaderText"]
        frozen_index = reader["currentIndex"]
        append(codex_second, {
            "timestamp": record_timestamp(1_100),
            "type": "response_item",
            "payload": {"type": "reasoning", "content": [{
                "type": "reasoning_text",
                "text": "CODEX_SECOND_CLEAN: fresh beta reasoning."
            }], "encrypted_content": "sealed"},
        })
        frozen = wait_for(lambda state:
            state.get("navigableCount") == 5 and
            state.get("checkerRequestInFlight") is False)
        # Opened on its session's newest message, the reader is live for that
        # session only; another session's message is counted on its tab.
        assert frozen["readerLive"] is True, frozen
        assert frozen["currentIndex"] == frozen_index, frozen
        assert frozen["messageReaderText"] == reader_text, frozen
        # Counted on its tab, or in the "+N ▾" menu when it is not shown.
        all_tabs = frozen["readerTabs"] + frozen["readerOverflowTabs"]
        assert any("Codex Beta" in tab and "(1 new)" in tab for tab in all_tabs), all_tabs

        get_json(API_BASE, "/close")
        resumed = wait_for(lambda state:
            state.get("uiStyle") == "single-line-ticker" and
            "CODEX_SECOND_CLEAN" in state.get("peekText", ""))
        assert resumed["currentIndex"] == 4, resumed
        assert resumed["peekSource"] == "Codex · Codex Beta", resumed

        # Revisit the first Claude session to prove interleaving is keyed by
        # transcript, not permanently stuck on whichever session appeared first.
        append(claude_path, {
            "timestamp": record_timestamp(1_200),
            "type": "assistant",
            "message": {"content": [{
                "type": "thinking",
                "thinking": "CLAUDE_ALPHA_RETURN_CLEAN: alpha resumed.",
                "signature": "sealed",
            }]},
        })
        alpha_return = wait_for(lambda state:
            "CLAUDE_ALPHA_RETURN_CLEAN" in state.get("peekText", "") and
            state.get("checkerRequestInFlight") is False)
        assert alpha_return["currentIndex"] == 5, alpha_return
        assert alpha_return["peekSource"] == "Claude · Claude Alpha", alpha_return

        # Claude Desktop stores normal chat thinking in a structured,
        # zstd-compressed chat_conversations response rather than Claude Code
        # JSONL. A new response must join the same ticker/checker flow with its
        # exact conversation title and exact plaintext thinking.
        write_claude_desktop_cache(claude_cache / "desktop-conversation_0", {
            "uuid": "desktop-conversation-1",
            "name": "Claude Desktop Exact Title",
            "updated_at": record_timestamp(1_300),
            "chat_messages": [{
                "uuid": "desktop-assistant-1",
                "sender": "assistant",
                "updated_at": record_timestamp(1_300),
                "content": [
                    {"type": "text", "text":
                     "CLAUDE_DESKTOP_RESPONSE_CLEAN: exact desktop response."},
                    {"type": "thinking",
                     "thinking": "CLAUDE_DESKTOP_CLEAN: exact desktop thinking.",
                     "summaries": [{"summary": "SUMMARY_MUST_STAY_EXCLUDED"}]},
                    {"type": "tool_result",
                     "content": "DESKTOP_TOOL_MUST_STAY_EXCLUDED"},
                ],
            }],
        })
        desktop = wait_for(lambda state:
            "CLAUDE_DESKTOP_CLEAN" in state.get("peekText", "") and
            state.get("checkerRequestInFlight") is False)
        assert desktop["currentIndex"] == 6, desktop
        assert desktop["peekSource"] == "Claude · Claude Desktop Exact Title", desktop

        audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
        reasoning_requests = [item for item in audit
            if item.get("action") == "external_reasoning_request"]
        reasoning_results = [item for item in audit
            if item.get("action") == "external_reasoning_result"]
        response_requests = [item for item in audit
            if item.get("action") == "external_assistant_response_request"]
        response_results = [item for item in audit
            if item.get("action") == "external_assistant_response_result"]
        requests = reasoning_requests + response_requests
        results = reasoning_results + response_results
        assert len(reasoning_requests) == 6, reasoning_requests
        assert len(reasoning_results) == 6, reasoning_results
        assert len(response_requests) == 2, response_requests
        assert len(response_results) == 2, response_results
        assert [item["status"] for item in results].count("alert") == 1, results
        assert [item["status"] for item in results].count("clean") == 7, results
        assert {item["request_id"] for item in requests} == \
            {item["request_id"] for item in results}, (requests, results)

        with DummyChecker.lock:
            all_sent = list(DummyChecker.requests)
        assert len(all_sent) == 8, all_sent
        assert "RESPONSE_CLEAN: done" in all_sent, all_sent
        assert "CLAUDE_DESKTOP_RESPONSE_CLEAN: exact desktop response." \
            in all_sent, all_sent
        assert "CLAUDE_DESKTOP_CLEAN: exact desktop thinking." in all_sent, all_sent
        assert all("SUMMARY_MUST_STAY_EXCLUDED" not in text for text in all_sent), all_sent
        assert all("DESKTOP_TOOL_MUST_STAY_EXCLUDED" not in text for text in all_sent), all_sent

        # Hide is an explicit user state. A later violation must persist and
        # update the menu/API without forcing the HUD back onscreen.
        get_json(API_BASE, "/hide")
        hidden_before_alert = wait_for(lambda state:
            state.get("windowVisible") is False and
            state.get("hiddenByUser") is True)
        append(claude_path, {
            "timestamp": record_timestamp(1_400),
            "type": "assistant",
            "message": {"content": [{
                "type": "text",
                "text": "HIDDEN_ALERT: violation while explicitly hidden",
            }]},
        })
        hidden_violation = wait_for(lambda state:
            state.get("violationCount") == 2 and
            state.get("checkerRequestInFlight") is False)
        assert hidden_violation["windowVisible"] is False, hidden_violation
        assert hidden_violation["hiddenByUser"] is True, hidden_violation
        assert hidden_violation["currentViolationVisible"] is False, hidden_violation
        assert hidden_violation["statusItemBadgeText"] == "2", hidden_violation
        assert hidden_violation["menuBarViolationAlertActive"] is True, hidden_violation
        get_json(API_BASE, "/violations")
        explicitly_revealed = wait_for(lambda state:
            state.get("windowVisible") is True and
            state.get("historyFilter") == "violations")
        assert explicitly_revealed["hiddenByUser"] is False, explicitly_revealed
        assert explicitly_revealed["visibleCardCount"] == 2, explicitly_revealed

        # "Flash Red, Then Show Bubble": the menu-bar icon is red first, then a
        # bubble shows the violation; the hidden window stays hidden and the
        # ticker selection does not change (BUG-074, BUG-094).
        get_json(API_BASE, "/close")
        ticker_before_transient = wait_for(lambda state:
            state.get("uiStyle") == "single-line-ticker")
        restore_index = ticker_before_transient["currentIndex"]
        get_json(API_BASE, "/hide")
        wait_for(lambda state: state.get("hiddenByUser") is True)
        # Flash only (the default): red, no bubble.
        get_json(API_BASE, "/violation-flash/on")
        wait_for(lambda state: state.get("violationFlashEnabled") is True)
        append(claude_path, {
            "timestamp": record_timestamp(1_450),
            "type": "assistant",
            "message": {"content": [{
                "type": "text",
                "text": "FLASH_ONLY_ALERT: red icon, no bubble",
            }]},
        })
        flash_only = wait_for(lambda state:
            state.get("violationCount") == 3 and
            state.get("statusItemFlashActive") is True)
        assert flash_only["statusItemDrawsFlashColor"] is True, flash_only
        assert flash_only["statusItemImageIsTemplate"] is False, flash_only
        assert flash_only["violationBubbleVisible"] is False, flash_only
        bubble_seen = []
        flash_done = wait_for(lambda state:
            bubble_seen.append(state.get("violationBubbleVisible")) or
            state.get("statusItemFlashActive") is False)
        assert flash_done["statusItemUsesNativeForeground"] is True, flash_done
        assert flash_done["statusItemImageIsTemplate"] is True, flash_done
        time.sleep(0.5)
        assert not any(bubble_seen) and \
            get_json(API_BASE, "/ui")["violationBubbleVisible"] is False, bubble_seen

        # Both: red first, then the bubble.
        get_json(API_BASE, "/violation-bubble/on")
        enabled = wait_for(lambda state:
            state.get("violationBubbleEnabled") is True)
        restore_index = enabled["currentIndex"]
        assert enabled["statusItemFlashActive"] is False, enabled
        assert enabled["violationBubbleVisible"] is False, enabled
        append(claude_path, {
            "timestamp": record_timestamp(1_500),
            "type": "assistant",
            "message": {"content": [{
                "type": "text",
                "text": "TRANSIENT_ALERT: show briefly when opted in",
            }]},
        })
        flashing = wait_for(lambda state:
            state.get("violationCount") == 4 and
            state.get("statusItemFlashActive") is True)
        assert flashing["violationBubbleVisible"] is False, flashing
        assert flashing["statusItemDrawsFlashColor"] is True, flashing
        # The flash is a regular (non-template) image in the violation color.
        assert flashing["statusItemImageIsTemplate"] is False, flashing
        assert flashing["windowVisible"] is False, flashing
        bubble = wait_for(lambda state:
            state.get("violationBubbleVisible") is True)
        assert bubble["statusItemFlashActive"] is False, bubble
        assert bubble["statusItemUsesNativeForeground"] is True, bubble
        assert bubble["statusItemDrawsFlashColor"] is False, bubble
        assert bubble["violationBubbleTitle"].startswith("Violation · "), bubble
        # The dummy checker quotes "ALERT" as its evidence.
        assert bubble["violationBubbleQuote"] == "\u201cALERT\u201d", bubble
        assert bubble["windowVisible"] is False, bubble
        assert bubble["hiddenByUser"] is True, bubble
        assert bubble["violationBubbleOnScreen"] is True, bubble
        frame, anchor = bubble["violationBubbleFrame"], bubble["statusItemWindowFrame"]
        if bubble["violationBubblePlacement"] == "under-icon":
            assert bubble["statusItemVisible"] is True, bubble
            assert frame["y"] + frame["height"] <= anchor["y"], (frame, anchor)
        else:
            assert bubble["violationBubblePlacement"] == "top-right", bubble
        restored = wait_for(lambda state:
            state.get("violationCount") == 4 and
            state.get("violationBubbleVisible") is False)
        assert restored["statusItemFlashActive"] is False, restored
        assert restored["statusItemUsesNativeForeground"] is True, restored
        assert restored["windowVisible"] is False, restored
        assert restored["hiddenByUser"] is True, restored
        # The ticker keeps following the newest ordinary item; the alert
        # never puts the new violation itself in the ticker.
        assert restored["currentIndex"] != restored["navigableCount"] - 1, \
            (restore_index, restored["currentIndex"], restored["navigableCount"])
        assert restored["currentViolationVisible"] is False, restored

        # Show Last Violation is an explicit action: it opens the newest
        # violation in the reader and undoes Hide.
        assert restored["lastViolationMenuTitle"] == "Show Last Violation", restored
        get_json(API_BASE, "/last-violation")
        last = wait_for(lambda state:
            state.get("uiStyle") == "full-message" and
            "TRANSIENT_ALERT" in (state.get("messageReaderText") or ""))
        assert last["windowVisible"] is True, last
        assert last["hiddenByUser"] is False, last
        # Opened while hidden: closing returns to hidden (BUG-100).
        assert last["returnsToHiddenOnClose"] is True, last
        get_json(API_BASE, "/close")
        rehidden = wait_for(lambda state: state.get("uiStyle") == "single-line-ticker")
        assert rehidden["windowVisible"] is False, rehidden
        assert rehidden["hiddenByUser"] is True, rehidden

        # Bubble only: no red step; clicking the bubble opens that violation.
        get_json(API_BASE, "/violation-flash/off")
        wait_for(lambda state: state.get("violationFlashEnabled") is False)
        get_json(API_BASE, "/close")
        get_json(API_BASE, "/hide")
        wait_for(lambda state: state.get("hiddenByUser") is True)
        append(claude_path, {
            "timestamp": record_timestamp(1_600),
            "type": "assistant",
            "message": {"content": [{
                "type": "text",
                "text": "BUBBLE_ALERT: open me from the bubble",
            }]},
        })
        wait_for(lambda state:
            state.get("violationCount") == 5 and
            state.get("violationBubbleVisible") is True and
            state.get("statusItemFlashActive") is False)
        get_json(API_BASE, "/violation-bubble/open")
        opened = wait_for(lambda state:
            state.get("uiStyle") == "full-message" and
            "BUBBLE_ALERT" in (state.get("messageReaderText") or ""))
        assert opened["violationBubbleVisible"] is False, opened
        assert opened["windowVisible"] is True, opened
        get_json(API_BASE, "/close")
        closed_bubble = wait_for(lambda state: state.get("uiStyle") == "single-line-ticker")
        assert closed_bubble["windowVisible"] is False, closed_bubble
        assert closed_bubble["hiddenByUser"] is True, closed_bubble
        # Show Thinkpeek undoes Hide for good: closing details keeps it shown.
        get_json(API_BASE, "/show")
        get_json(API_BASE, "/violations")
        get_json(API_BASE, "/close")
        shown = wait_for(lambda state: state.get("uiStyle") == "single-line-ticker")
        assert shown["windowVisible"] is True and shown["hiddenByUser"] is False, shown
        get_json(API_BASE, "/violation-bubble/off")

        print(json.dumps({
            "concurrentProviders": ["Claude", "Codex"],
            "simulatedConversations": 5,
            "dummyRequests": len(all_sent),
            "outOfOrderResults": True,
            "alertAndClean": True,
            "autoFollowedAcrossSessions": True,
            "readerFrozeThenResumed": True,
            "hiddenViolationStayedHidden": hidden_before_alert["windowVisible"] is False,
            "defaultFlashOnBubbleOff": True,
            "flashOnlyHadNoBubble": True,
            "flashThenBubbleKeptHidden": restored["hiddenByUser"] is True,
            "lastViolationOpened": True,
            "bubbleOpenedViolation": True,
            "providerTitles": ["Claude Alpha", "Claude Beta",
                               "Codex Alpha", "Codex Beta",
                               "Claude Desktop Exact Title"],
            "claudeDesktopCacheObserved": True,
            "encryptedAndToolsExcluded": True,
            "localSummaryDisplayedButNotSent": True,
            "assistantResponseCheckedButNotDisplayedAsThought": True,
            "tickerNavigation": "alert-to-clean",
            "checkerLightObserved": True,
            "claudeCloudLifecycleObserved": True,
            "claudeWaitingLifecycleObserved": True,
            "auditPairs": len(results),
            "uiAPIAuthentication": "required",
            "uiAPIMutations": "post-only",
            "uiAPIBinding": "127.0.0.1",
            "renderedScreenshotBytes": len(screenshot),
        }, sort_keys=True))
    except BaseException:
        # Keep the command log (with each command's origin: http or appKit)
        # so a failure can be traced to its cause instead of retried.
        kept = Path(".local") / "last-failed-e2e-ui-api.jsonl"
        kept.parent.mkdir(exist_ok=True)
        if ui_log_path.exists():
            kept.write_text(ui_log_path.read_text())
        if audit_path.exists():
            (Path(".local") / "last-failed-e2e-audit.jsonl").write_text(audit_path.read_text())
        raise
    finally:
        try:
            get_json(API_BASE, "/violation-bubble/off")
        except Exception:
            pass
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
