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
    echo "Thoughtcrime post-commit restart already running; skipped $commit"
    exit 0
fi
cleanup() {
    rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

echo "Thoughtcrime: rebuilding $commit after commit"
{
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') rebuilding $commit"
    if ! (cd "$repo_root" && ./build.sh); then
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') build failed; running app left unchanged"
        exit 1
    fi

    # LaunchServices owns the app process, so it survives Git exiting without
    # becoming a restartable service. SingleInstance replaces the old copy once.
    /usr/bin/open -n -g "$repo_root/.build/Thoughtcrime.app"
    sleep 1
    /usr/bin/pgrep -x thoughtcrime >/dev/null
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') opened app bundle for $commit"
} >> "$restart_log" 2>&1

echo "Thoughtcrime: rebuilt and opened replacement once; log: $restart_log"
