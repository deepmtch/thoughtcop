#!/bin/sh
set -eu

cd "$(dirname "$0")"

needs_build=false
if [ ! -x .build/ThoughtCop.app/Contents/MacOS/thoughtcop ] ||
   [ ! -f .build/build.stamp ] ||
   [ build.sh -nt .build/build.stamp ] ||
   [ Resources/ThoughtCop-Info.plist -nt .build/build.stamp ] ||
   /usr/bin/find Sources Tests -type f -newer .build/build.stamp -print -quit | /usr/bin/grep -q .; then
    needs_build=true
fi

if [ "$needs_build" = true ]; then
    echo "thoughtcop: building changed sources..."
    ./build.sh
else
    echo "thoughtcop: build is current"
fi

old_pid=$(/usr/bin/pgrep -x thoughtcop 2>/dev/null | /usr/bin/head -n 1 || true)
api_port=${THOUGHTCOP_API_PORT:-17321}
api_token_path=${THOUGHTCOP_UI_API_TOKEN_PATH:-"$HOME/Library/Application Support/ThoughtCop/ui-api-token"}

api_ready() {
    printf 'Authorization: Bearer %s\n' "$api_token" |
        /usr/bin/curl --header @- --fail --silent --max-time 0.2 \
            "http://127.0.0.1:$api_port/ui" >/dev/null 2>&1
}

# LaunchServices owns the GUI process, so this command returns to the shell.
# The new process uses SingleInstance.swift to terminate the previous ThoughtCop
# only after the build and launch both succeed.
/usr/bin/open -n -g "$(pwd)/.build/ThoughtCop.app" "$@"
echo "thoughtcop: launched replacement; verifying..."

attempt=0
while [ "$attempt" -lt 100 ]; do
    running=$(/usr/bin/pgrep -x thoughtcop 2>/dev/null || true)
    count=$(printf '%s\n' "$running" | /usr/bin/awk 'NF { n += 1 } END { print n + 0 }')
    new_pid=$(printf '%s\n' "$running" | /usr/bin/head -n 1)
    api_token=${THOUGHTCOP_UI_API_TOKEN:-}
    if [ -z "$api_token" ] && [ -r "$api_token_path" ]; then
        api_token=$(/bin/cat "$api_token_path")
    fi
    if [ "$count" -eq 1 ] && [ -n "$new_pid" ] &&
       { [ -z "$old_pid" ] || [ "$new_pid" != "$old_pid" ]; } &&
       [ -n "$api_token" ] &&
       api_ready; then
        echo "thoughtcop: replacement verified; pid $new_pid"
        exit 0
    fi
    attempt=$((attempt + 1))
    /bin/sleep 0.1
done

echo "thoughtcop: replacement did not reach one verified new process" >&2
exit 1
