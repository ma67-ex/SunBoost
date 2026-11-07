#!/bin/bash
# Builds ./sunboost. Needs Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O -swift-version 5 sunboost.swift -o sunboost
./sunboost --selftest
echo "Built ./sunboost"
