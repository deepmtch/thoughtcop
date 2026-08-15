#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
state_dir="$repo_root/.local/post-commit"
request_file="$state_dir/requested"
lock_dir="$state_dir/worker.lock"
pid_file="$lock_dir/pid"
restart_log="$state_dir/restart.log"
app_log="$state_dir/app.log"

mkdir -p "$state_dir"

if [ "${1:-}" != "--worker" ]; then
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$request_file"
    if [ -f "$pid_file" ]; then
        worker_pid=$(cat "$pid_file" 2>/dev/null || true)
        if [ -n "$worker_pid" ] && ! kill -0 "$worker_pid" 2>/dev/null; then
            rm -f "$pid_file"
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi
    if mkdir "$lock_dir" 2>/dev/null; then
        nohup "$0" --worker >> "$restart_log" 2>&1 </dev/null &
        echo "$!" > "$pid_file"
        echo "Thinkpeek rebuild/restart queued; log: $restart_log"
    else
        echo "Thinkpeek rebuild already running; latest commit queued"
    fi
    exit 0
fi

cleanup() {
    rm -f "$pid_file"
    rmdir "$lock_dir" 2>/dev/null || true
    if [ -f "$request_file" ]; then
        "$0" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

while [ -f "$request_file" ]; do
    rm -f "$request_file"
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') rebuilding $(git -C "$repo_root" rev-parse --short HEAD)"
    if ! (cd "$repo_root" && ./build.sh); then
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') build failed; running app left unchanged"
        exit 1
    fi
done

(
    cd "$repo_root"
    nohup ./.build/thinkpeek >> "$app_log" 2>&1 </dev/null &
)
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') launched verified build"
