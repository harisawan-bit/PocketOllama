# PocketOllama (iOS Local AI Server)

Turn a modern iPhone into a local OpenAI- and Ollama-compatible inference server over Wi-Fi.
Real GGUF inference runs on the Apple Silicon GPU through [llama.cpp](https://github.com/ggml-org/llama.cpp),
pinned to release **b11218**.

- **Engine:** llama.cpp b11218 (prebuilt Apple XCFramework, `ios-arm64`, Metal kernels embedded)
- **Minimum iOS:** 16.4 (set by the llama.xcframework)
- **API:** OpenAI `/v1/chat/completions`, Ollama `/api/chat`, `/api/tags`, embedded web console at `/`
- **Discovery:** Bonjour `_ollama._tcp`, default port 11434

---

## Install

The published IPA is **unsigned**. Re-sign it with AltStore, Sideloadly, or ESign using your Apple ID.
The embedded `llama.framework` is re-signed along with the app by these tools.

1. Download `PocketOllama.ipa` from the [releases page](https://github.com/harisawan-bit/PocketOllama/releases).
2. Install via AltStore, Sideloadly, or ESign.
3. On first launch, allow **Local Network** access when prompted.

Free Apple ID installs expire after 7 days; re-sign to renew. The
`com.apple.developer.kernel.increased-memory-limit` entitlement is not present in a personal
provisioning profile, so the app runs under the standard iOS process memory ceiling. The in-app
memory budget check accounts for this and refuses a model that will not fit.

## First run

1. **Models** tab, pick a curated model and download it (about 400 MB to 5 GB).
2. Tap **Load** on the downloaded model. The context size is chosen from the model metadata and the
   measured available memory; a model that will not fit is rejected with the required/available MB.
3. **Playground** tab, send a prompt. Or tap **Start Local AI Server** on the Dashboard and use the API
   from a laptop on the same network.

## Laptop clients

```bash
# Windows
.\ClientScripts\setup_laptop.ps1

# macOS / Linux
chmod +x ./ClientScripts/setup_laptop.sh
./ClientScripts/setup_laptop.sh
```

Point any OpenAI-compatible client at `http://<iphone-ip>:11434/v1`. With Bonjour, `http://iphone-ai.local:11434/v1`
resolves on the local network while the server is running.

### Hermes agent loop

```bash
python ClientScripts/hermes_agent_runner.py "Inspect git status and list files modified today"
```

Requires a tool-trained model such as Hermes 3.

### Benchmark

```bash
python ClientScripts/benchmark_harness.py
```

Reports real time-to-first-token and tokens/second measured by the in-app benchmark engine.

## Verified model URLs

| Model | File | Size | Notes |
|---|---|---|---|
| Qwen2.5 0.5B Instruct | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | ~400 MB | Fastest smoke test |
| DeepSeek-R1-Distill-Qwen-1.5B | `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf` | ~1.1 GB | Reasoning traces |
| Hermes 3 Llama 3.2 3B | `Hermes-3-Llama-3.2-3B.Q4_K_M.gguf` | ~2.1 GB | Tool calling |
| Hermes 3 Llama 3.1 8B | `Hermes-3-Llama-3.1-8B.Q4_K_M.gguf` | ~4.9 GB | 8 GB devices only |

You can also drop any `.gguf` file into `Documents/models` through Finder or the Files app
(file sharing is enabled), then load it from the Models tab.

## Hardware guidance

| Device | RAM | Comfortable model | Threads | Max safe context |
|---|---|---|---|---|
| iPhone 16 Pro / Max (A18 Pro) | 8 GB | Hermes 3 8B Q4_K_M | 4 | 32k |
| iPhone 16 / Plus (A18) | 8 GB | Hermes 3 8B Q4_K_M | 4 | 16k |
| iPhone 15 Pro / Max (A17 Pro) | 8 GB | Hermes 3 8B Q4_K_M | 4 | 16k |
| iPhone 15 / 15 Plus (A16) | 6 GB | Hermes 3 3B | 3 | 8k |
| iPhone 14 Pro / Max (A16) | 6 GB | Hermes 3 3B | 3 | 8k |
| iPhone 13 / 14 (A15) | 6 GB | Llama 3.2 3B | 3 | 8k |

Context limits are clamped against measured available memory at load time, so a device with less free
RAM than the table implies will get a smaller context rather than a crash.

## Security

The server binds every Wi-Fi interface. On a shared or untrusted network, set an
API key in **Settings -> Engine Configuration -> Remote Access Authentication**.
`/v1/*` and `/api/*` then require `Authorization: Bearer <key>`. The health
endpoint and the web dashboard stay reachable so the key can be entered there.

## Known limits

- **The app must stay in the foreground.** iOS suspends a suspended app, and this
  app declares no background mode, so the HTTP server and inference both stop when
  you switch apps or lock the screen. There is deliberately no fake audio session
  pretending otherwise. Keep the app open while serving.
- Nightstand mode dims the display and keeps the screen awake, but it cannot
  outrun iOS backgrounding.


- iOS 16.4 or later, device only. There is no simulator slice of the pinned XCFramework.
- The IPA is unsigned and requires re-signing to install.
- No increased-memory-limit entitlement under a personal provisioning profile, so the largest models
  only fit on 8 GB devices.
- `mlock` of model weights is best effort. It fails without the entitlement, so the app does not
  depend on it and does not claim it succeeded unless the call returned 0.
- Tool calling depends on the model being trained for it. Non-tool models will answer in prose.

## Build

The Xcode project is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.
There is no committed `.xcodeproj`.

```bash
./Scripts/fetch_llama.sh      # downloads and caches the pinned xcframework
xcodegen generate
xcodebuild build -project PocketOllama.xcodeproj -scheme PocketOllama \
  -destination "generic/platform=iOS" -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

CI (`.github/workflows/build-ipa.yml`) runs on `macos-15` and additionally enforces:

- `Scripts/verify_no_stubs.sh`: fails the build if the old canned-response generator, fake token
  pacing, or hardcoded capability claims reappear in the Swift sources.
- a linkage gate that fails unless `llama.framework` is embedded, the app links it, the app imports
  `llama_model_load_from_file`, and the framework carries its Metal kernels.

To cut a release, set `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`
(XcodeGen generates the Info.plist from it, so editing the plist directly has no effect), then:

```bash
git tag v2.2.3 && git push origin v2.2.3
```

## License

The llama.cpp XCFramework is built from the upstream release and is distributed under the MIT license.
