# 📱 PocketOllama (iOS Local AI Server)

> Turn any modern iPhone into an ultra-fast, local OpenAI & Ollama-compatible AI inference server over Wi-Fi and USB, engineered for **CPU-only laptops, Hermes Agent loops, test harnesses (SWE-bench, Aider, lm-eval), and 100% crash-proof overnight runs**.

[![Build Sideloadable IPA](https://img.shields.io/badge/Build-GitHub%20Actions%20CI-blue.svg)]()
[![iOS: 16.0+](https://img.shields.io/badge/iOS-16.0+-black.svg?logo=apple)]()
[![Metal: Accelerated](https://img.shields.io/badge/Metal-GPU%20Unified-purple.svg)]()
[![OpenAI: Compatible](https://img.shields.io/badge/API-OpenAI%20%2F%20Ollama-emerald.svg)]()

---

## ⚡ Key Highlights

- **Bento Grid UI & Cyber Design**: Built from scratch with Apple HIG and modern cyber aesthetics, featuring live tokens/sec speedometer, RAM pressure telemetry, and interactive context sliders.
- **On-Device Chat & Collapsible Thinking Accordion**: Native on-device chat playground displaying live token stream speed and collapsible `<think>` / `<scratchpad>` reasoning traces.
- **Hermes Agent Mastery**: Built-in bidirectional bridge for Nous Hermes XML (`<tools>`, `<tool_call>`, `<scratchpad>`, `<plan>`), allowing standard OpenAI SDK scripts on your laptop to execute multi-turn autonomous tool loops seamlessly.
- **100% Crash-Proof Reliability Shield**:
  - **Jetsam & RAM Scavenger**: Pre-flight memory checks + Darwin Mach VM pressure relief (`malloc_zone_pressure_relief`) prevent Out-Of-Memory kernel kills.
  - **Memory Locking (`mlock`)**: Locks model weight pages in physical wired RAM with zero virtual memory paging stutter.
  - **Chunked Metal Prefill (`ubatch: 256`)**: Defeats iOS GPU watchdog timer on large 12k+ token prompts.
  - **`SIGPIPE` Immunity**: Survives abrupt laptop disconnects without crashing.
  - **Middle-Out Context Compactor**: Safely compresses oversized prompts without assertion failures.
- **Overnight Insomnia Nightstand Mode**: Pure OLED `#000000` screen saver draws 0% display power and emits zero light in a dark room while running inference all night.
- **Auto-Discovery via Bonjour / mDNS**: Connects to `http://iphone-ai.local:11434/v1` automatically without needing to check changing DHCP IP addresses.

---

## 📱 Universal iPhone Hardware Optimization Matrix

The app automatically reads `sysctlbyname("hw.machine")` and `ProcessInfo.physicalMemory` on boot to configure the optimal memory envelope, thread count, and context limits:

| iPhone Generation | Identifier | SoC / GPU | RAM | Max Recommended Model | Threads | Max Safe Context | KV Quant |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **iPhone 16 Pro / Max** | `iPhone17,1`, `iPhone17,2` | A18 Pro (6-core) | **8 GB** | **Hermes 3 8B (Q4_K_M)** / DeepSeek-R1-7B | 4 | **16k – 32k** | `Q4_0` / `Q8_0` |
| **iPhone 16 / 16 Plus / 16e** | `iPhone17,3`, `iPhone17,4` | A18 (5-core) | **8 GB** | **Hermes 3 8B (Q4_K_M)** / Llama 3.2 3B | 4 | **16k** | `Q4_0` |
| **iPhone 15 Pro / Max** | `iPhone16,1`, `iPhone16,2` | A17 Pro (6-core) | **8 GB** | **Hermes 3 8B (Q4_K_M)** / Qwen 2.5 7B | 4 | **16k** | `Q4_0` |
| **iPhone 15 / 15 Plus** | `iPhone15,4`, `iPhone15,5` | A16 Bionic (5-core) | **6 GB** | **Hermes 3 3B** / Llama 3.2 3B / Phi-3.5 | 3 | **8k** | `Q8_0` |
| **iPhone 14 Pro / Max** | `iPhone15,2`, `iPhone15,3` | A16 Bionic (5-core) | **6 GB** | **Hermes 3 3B** / Qwen 2.5 3B | 3 | **8k** | `Q8_0` |
| **iPhone 13 Pro / 14 base** | `iPhone14,2`, `iPhone14,7` | A15 Bionic (5-core) | **6 GB** | **Llama 3.2 3B** / Qwen 2.5 3B | 3 | **8k** | `Q8_0` |
| **iPhone 12 / 13 base** | `iPhone13,2`, `iPhone14,5` | A14 / A15 Bionic | **4 GB** | **Llama 3.2 1B** / Qwen 2.5 1.5B | 2 | **4k** | `Q4_0` |
| **iPhone 11 Series** | `iPhone12,1`, `iPhone12,3` | A13 Bionic | **4 GB** | **Llama 3.2 1B** / SmolLM2 1.7B | 2 | **2k** | `Q4_0` |

---

## 💻 1-Line Laptop Client Setup

### Windows (PowerShell)
```powershell
.\ClientScripts\setup_laptop.ps1
```

### macOS / Linux (Bash / Zsh)
```bash
chmod +x ./ClientScripts/setup_laptop.sh
./ClientScripts/setup_laptop.sh
```

---

## 🤖 Running Hermes Agent with Autonomous Tool Calling

Run an autonomous coding and shell agent powered entirely by your iPhone:

```bash
python ClientScripts/hermes_agent_runner.py "Inspect git status and list all files modified today"
```

---

## 🧪 Running the Benchmark & Test Harness

Measure Time-To-First-Token (TTFT), tokens/sec, and fetch hardware context telemetry:

```bash
python ClientScripts/benchmark_harness.py
```

---

## 🌙 Running All Night (Insomnia Nightstand Mode)

1. Connect your iPhone to a MagSafe charger on your nightstand or desk.
2. Start the server in PocketOllama.
3. Tap **"Enter Insomnia Nightstand Mode"**.
4. The display turns pure black (`#000000`), consuming 0% OLED power, while keeping Apple Silicon Metal compute at full speed for 12+ hours.
