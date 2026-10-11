# Requirements

What PocketOllama needs to build, and what it needs at runtime. Every tool
below is pinned to the version CI actually uses, so a mismatch between this
file and a failing build is a bug worth reporting.

## To build

| Requirement | Version | Notes |
|---|---|---|
| macOS | 15 (CI) | The XCFramework slice is `ios-arm64` only, so the build host must be macOS |
| Xcode | 16.x | Whatever ships with the macOS 15 runner image |
| XcodeGen | 9.x | Generates the project from `project.yml`. There is no committed `.xcodeproj` |
| Git | any | Used to fetch nothing; the framework comes from a release download |
| A shell | bash | `Scripts/fetch_llama.sh`, `Scripts/verify_no_stubs.sh` |

Nothing else. There is no CocoaPods, no Carthage, and no SwiftPM manifest, so
there is no dependency resolution step beyond downloading one zip.

## Dependencies

| Dependency | Version | Source | Why |
|---|---|---|---|
| llama.cpp XCFramework | `b11218` | [upstream release](https://github.com/ggml-org/llama.cpp/releases) | Real GGUF inference with Metal kernels |

`Scripts/fetch_llama.sh` downloads it into `Vendor/llama.xcframework` and
verifies the archive before use. That directory is gitignored, so the binary
is never committed.

## To run (on device)

| Requirement | Value | Why |
|---|---|---|
| iOS | **16.4 or later** | Set by the XCFramework's own `MinimumOSVersion` |
| Device | iPhone, iPad, or Apple Silicon Mac (Catalyst) | 64-bit, Metal-capable |
| RAM | 2 GB minimum, 8 GB for the 8B tier | Inference is memory bound |
| Free disk | model size plus ~15% | KV cache and iOS scratch space |
| Network | Local Wi-Fi, for the HTTP API | The app serves over the LAN |
| Code signing | A signing identity | The IPA ships unsigned |

## Software prerequisites for the laptop clients

Optional, only if you drive the phone from a laptop.

| Tool | Used by |
|---|---|
| Python 3.9+ | `ClientScripts/benchmark_harness.py`, `ClientScripts/hermes_agent_runner.py` |
| `requests` | Both Python clients |
| PowerShell 5.1+ | `ClientScripts/setup_laptop.ps1` (Windows path) |
| bash | `ClientScripts/setup_laptop.sh` (macOS/Linux path) |
