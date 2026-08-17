#!/bin/sh
set -eu

cd "$(dirname "$0")"
./build.sh

# LaunchServices owns the GUI process, so this command returns to the shell.
# The new process uses SingleInstance.swift to terminate the previous Thinkpeek
# only after the build and launch both succeed.
/usr/bin/open -n -g "$(pwd)/.build/Thinkpeek.app" "$@"
echo "thinkpeek: opened rebuilt app; replacement continues in LaunchServices"
