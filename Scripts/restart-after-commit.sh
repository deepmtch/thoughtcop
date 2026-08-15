#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
state_dir="$repo_root/.local/post-commit"
lock_dir="$state_dir/restart.lock"
restart_log="$state_dir/restart.log"
app_log="$state_dir/app.log"
commit=$(git -C "$repo_root" rev-parse --short HEAD)

mkdir -p "$state_dir"

if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "Thinkpeek post-commit restart already running; skipped $commit"
    exit 0
fi
cleanup() {
    rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

echo "Thinkpeek: rebuilding $commit after commit"
{
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') rebuilding $commit"
    if ! (cd "$repo_root" && ./build.sh); then
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') build failed; running app left unchanged"
        exit 1
    fi

    # launchctl owns the replacement process, so it survives Git and terminal
    # process cleanup. SingleInstance replaces the old app only after this build.
    job_label="com.thinkpeek.postcommit.$commit.$PPID"
    /bin/launchctl submit -l "$job_label" -o "$app_log" -e "$app_log" -- \
        "$repo_root/.build/thinkpeek"
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') submitted $commit as $job_label"
} >> "$restart_log" 2>&1

echo "Thinkpeek: rebuilt and restart submitted; log: $restart_log"
