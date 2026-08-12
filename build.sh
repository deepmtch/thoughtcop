#!/bin/sh
set -eu

module_cache="${TMPDIR:-/tmp}/thinkpeek-swift-module-cache"
mkdir -p "$module_cache"

swiftc -O -swift-version 5 -module-cache-path "$module_cache" -o thinkpeek \
    Config.swift \
    Transcript.swift \
    Sessions.swift \
    DriftCheck.swift \
    SingleInstance.swift \
    UIStateServer.swift \
    Views.swift \
    HUD.swift \
    main.swift
