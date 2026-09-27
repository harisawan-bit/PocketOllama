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

# The web dashboard must never assign anything to innerHTML. The model output is
# untrusted and the API key lives in localStorage in that same origin, so markup
# in a model response was able to run script and read the key.
if grep -E 'innerHTML[[:space:]]*=' PocketOllama/Server/WebDashboardHTML.swift > /dev/null; then
    echo "FAIL: WebDashboardHTML assigns to innerHTML; model output is untrusted." >&2
    fail=1
else
    echo "ok   dashboard never assigns to innerHTML"
fi

# Engine errors must carry a message, or every error site renders blank.
if grep -q 'var errorDescription' PocketOllama/Inference/LlamaEngine.swift; then
    echo "ok   engine errors carry messages"
else
    echo "FAIL: LlamaEngineError has no errorDescription." >&2
    fail=1
fi

# The thread Stepper must actually reach the engine, not just the UI.
if grep -q 'setBaseThreads(count)' PocketOllama/Core/ConfigEngine.swift; then
    echo "ok   thread choice reaches the thermal governor"
else
    echo "FAIL: ConfigEngine never pushes threadCount to the governor." >&2
    fail=1
fi

exit $fail

