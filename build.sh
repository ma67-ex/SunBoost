#!/bin/bash
# Builds the command line tool ./sunboost. Needs Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O -swift-version 5 Sources/Shared/Booster.swift Sources/CLI/main.swift -o sunboost
./sunboost --selftest
echo "Built ./sunboost"
