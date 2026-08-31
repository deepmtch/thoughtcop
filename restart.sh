#!/bin/sh
set -eu

cd "$(dirname "$0")"
./build.sh

old_pid=$(/usr/bin/pgrep -x thinkpeek 2>/dev/null | /usr/bin/head -n 1 || true)

# LaunchServices owns the GUI process, so this command returns to the shell.
# The new process uses SingleInstance.swift to terminate the previous Thinkpeek
# only after the build and launch both succeed.
/usr/bin/open -n -g "$(pwd)/.build/Thinkpeek.app" "$@"

attempt=0
while [ "$attempt" -lt 100 ]; do
    running=$(/usr/bin/pgrep -x thinkpeek 2>/dev/null || true)
    count=$(printf '%s\n' "$running" | /usr/bin/awk 'NF { n += 1 } END { print n + 0 }')
    new_pid=$(printf '%s\n' "$running" | /usr/bin/head -n 1)
    if [ "$count" -eq 1 ] && [ -n "$new_pid" ] &&
       { [ -z "$old_pid" ] || [ "$new_pid" != "$old_pid" ]; }; then
        echo "thinkpeek: replacement verified; pid $new_pid"
        exit 0
    fi
    attempt=$((attempt + 1))
    /bin/sleep 0.1
done

echo "thinkpeek: replacement did not reach one verified new process" >&2
exit 1
