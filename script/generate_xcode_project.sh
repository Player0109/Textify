#!/usr/bin/env bash
set -euo pipefail

command -v xcodegen >/dev/null || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
}

xcodegen generate --spec project.yml
