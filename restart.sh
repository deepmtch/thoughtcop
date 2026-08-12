#!/bin/sh
set -eu

cd "$(dirname "$0")"
./build.sh

# The new process uses SingleInstance.swift to terminate the previous Thinkpeek
# only after this build succeeds.
exec ./thinkpeek "$@"
