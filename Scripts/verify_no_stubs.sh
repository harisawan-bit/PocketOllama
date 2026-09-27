#!/usr/bin/env bash
set -euo pipefail
fail=0
check() {
  if grep -rn "$1" PocketOllama --include=*.swift >/dev/null; then
    echo "BANNED PATTERN: $2"
    grep -rn "$1" PocketOllama --include=*.swift | head
    fail=1
  fi
}
check "generateDynamicResponse" "canned-answer generator"
check "Task.sleep(nanoseconds: 22_000_000)" "fake token pacing"
check "simulated" "simulated output"
check "metal zero-copy UMA" "false capability claim in logs"
check "Inference completed via PocketOllama" "canned non-stream response"
exit $fail
