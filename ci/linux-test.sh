#!/usr/bin/env bash
# Linux job (docker/linux-core.Dockerfile). Builds and tests whatever Package.swift exposes on
# Linux; Apple-only targets must be gated behind canImport(AppKit) (docs/ci-cd.md §4).
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift build --scratch-path "${SWIFT_SCRATCH:-.build-linux}" --build-tests
swift test --scratch-path "${SWIFT_SCRATCH:-.build-linux}" --skip-build --parallel
