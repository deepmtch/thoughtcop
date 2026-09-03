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
    host_port = base.removeprefix("http://")
    host, port_text = host_port.rsplit(":", 1)
    with socket.create_connection((host, int(port_text)), timeout=3) as connection:
        connection.sendall(
            f"GET {path} HTTP/1.1\r\nHost: {host_port}\r\nConnection: close\r\n\r\n"
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
    if not separator or b" 200 " not in header.split(b"\r\n", 1)[0]:
        raise RuntimeError(f"invalid API response: {response[:200]!r}")
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
        initial = wait_for(lambda state: state.get("initialScanComplete") is True,
                           timeout=20, process=process,
                           diagnostic_log=ui_log_path)
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
        assert both_active["peekSource"] == "Codex · Codex Alpha", both_active
        assert both_active["peekText"] == "Working…", both_active

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
        assert finished["currentViolationVisible"] is True, finished
        assert finished["peekSource"] == "Claude · Claude Alpha", finished
        assert "Dummy detected explicit Claude uncertainty" in finished["peekText"], finished
        assert "unavailable" not in finished["peekText"].lower(), finished
        assert finished["tickerAlarmActive"] is True, finished
        assert finished["windowVisible"] is True, finished
        assert len(finished["violations"]) == 1, finished
        assert finished["violations"][0]["checkPrompt"], finished

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
        assert violation_list["latestControlVisible"] is True, violation_list
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
        reader = wait_for(lambda state: state.get("messageReaderFrozen") is True)
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
        assert frozen["messageReaderFrozen"] is True, frozen
        assert frozen["currentIndex"] == frozen_index, frozen

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

        print(json.dumps({
            "concurrentProviders": ["Claude", "Codex"],
            "simulatedConversations": 5,
            "dummyRequests": len(all_sent),
            "outOfOrderResults": True,
            "alertAndClean": True,
            "autoFollowedAcrossSessions": True,
            "readerFrozeThenResumed": True,
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
