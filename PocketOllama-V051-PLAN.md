# PocketOllama v0.5.1 - Research and Plan

Research date: 2026-10-11. Every technical claim below was verified against
primary sources in this session: the pinned `b11218` XCFramework binary, the
`b11218` source tree on GitHub, `include/llama.h`, `ggml/include/ggml-rpc.h`,
`tools/rpc/README.md`, and two peer-reviewed papers (arXiv 2503.14882,
MDI-LLM).

---

## 0. Measured baseline (on a real iPhone, 192.168.1.4)

These are numbers taken from live requests, not estimates.

| Metric | Value |
|---|---|
| Decode throughput | ~53 tok/s (Qwen3.5-0.8B-Q4_0) |
| Decode stability over 8 requests | +5% drift, no thermal throttling |
| Prefill throughput | ~850 tok/s |
| Longest context tested | 6018 prompt tokens |
| Concurrency | 1 runs, 4 get 503 `server_busy` in 0.13s |
| Self-checks | 131/131 |
| `/health` | `{"status":"healthy","runtime":"Metal"}` |

---

## 1. The blocking finding: RPC is NOT in the shipped XCFramework

I downloaded the real `llama-b11218-xcframework.zip` (60,915,933 bytes) and
probed the `ios-arm64/llama.framework/llama` binary (11,223,128 bytes) directly.

| Symbol | Present |
|---|---|
| `ggml_backend_metal` | FOUND (control) |
| `llama_model_load_from_file` | FOUND (control) |
| `ggml_backend_rpc_init` | **absent** |
| `ggml_backend_rpc_buffer_type` | **absent** |
| `GGML_RPC` | **absent** |

Cause, from `build-xcframework.sh` at b11218: `COMMON_CMAKE_ARGS` passes
`-DGGML_METAL=ON` but **never `-DGGML_RPC=ON`**. The official iOS XCFramework is
built without the RPC backend. It is not a flag we forgot; upstream does not ship
it for iOS.

**Consequence:** linking iPhones to split a model cannot be done with the current
dependency. It requires building llama.cpp from source. Everything else in this
plan is unaffected.

---

## 2. Feasibility of an iOS RPC build: GOOD

I read the RPC sources rather than assuming. This is more portable than expected.

`tools/rpc/rpc-server.cpp` (254 lines)
- Includes: `ggml-backend.h`, `ggml-rpc.h`, plus C++ stdlib. **No POSIX socket
  headers, no `unistd` socket calls.**
- Only 3 platform guards, all `__linux__` (for a `pwd.h`-based home lookup).

`ggml/src/ggml-rpc/transport.cpp` (798 lines)
- Contains the actual sockets (`socket`, `bind`, `listen`, `accept`, `connect`,
  `setsockopt`) and has **zero platform guards**. BSD sockets are identical on
  iOS, so this compiles for iOS unchanged.
- Clean pimpl interface in `transport.h`: `create_server(host, port)`,
  `connect(host, port)`, `send_data`, `recv_data`, `flush`.

`ggml/src/ggml-rpc/CMakeLists.txt`
- `ggml_add_backend_library(ggml-rpc ggml-rpc.cpp transport.cpp)`, portable.
- RDMA on Apple uses `librdma.dylib` (macOS 26.2+, Thunderbolt 5) linked
  **weakly**. No iPhone has Thunderbolt, so RDMA is macOS-host-only. It must stay
  OFF for iOS.

Verdict: an iOS RPC build is real engineering, but a tractable one. The blocker
is that it needs macOS + Xcode to produce and verify, which this environment does
not have.

---

## 3. The real client API (verified names from `ggml-rpc.h`)

```
#define RPC_PROTO_MAJOR_VERSION 7
#define GGML_RPC_MAX_SERVERS    16

ggml_backend_t        ggml_backend_rpc_init(const char * endpoint, uint32_t device);
bool                  ggml_backend_is_rpc(ggml_backend_t backend);
ggml_backend_buffer_type_t ggml_backend_rpc_buffer_type(const char * endpoint, uint32_t device);
void                  ggml_backend_rpc_get_device_memory(const char * endpoint, uint32_t device,
                                                         size_t * free, size_t * total);
void                  ggml_backend_rpc_start_server(const char * endpoint, const char * cache_dir,
                                                    size_t n_threads, size_t n_devices,
                                                    ggml_backend_dev_t * devices);
ggml_backend_reg_t    ggml_backend_rpc_add_server(const char * endpoint);
```

Two facts that shape the design:

- **`ggml_backend_rpc_get_device_memory` returns each peer's free and total
  RAM.** That is exactly what a cluster coordinator needs to decide how to split.
  No guessing.
- **`GGML_RPC_MAX_SERVERS` is 16.** The ceiling on cluster size is 16 devices.

Splitting itself is not new code: `mparams.tensor_split` already exists and the
README confirms "llama.cpp distributes model weights and the KV cache across all
available devices in proportion to each device's available memory," overridable
with `--tensor-split`.

---

## 4. Upstream's own warning, which we must respect

From `tools/rpc/README.md`:

> This example and the RPC backend are currently in a proof-of-concept
> development stage. As such, the functionality is fragile and insecure. **Never
> run the RPC server on an open network or in a sensitive environment!**

The RPC protocol has **no authentication and no encryption**. This app serves on
Wi-Fi by design. Therefore:

- RPC must be **off by default** and require explicit opt-in per peer.
- RPC must be restricted to the local subnet and refuse non-private addresses.
- The UI must state plainly that RPC traffic is unauthenticated and unencrypted.
- This is a hard requirement, not a nice-to-have. Shipping an open RPC port on a
  coffee-shot Wi-Fi would be a genuine security defect.

---

## 5. What the research says about whether this is even worth it

**AirComp (arXiv 2503.14882).** Tensor parallelism across edge devices, using
over-the-air computation: it exploits the physical fact that radio waves
superpose, so the wireless channel itself performs the all-reduce. Reports up to
**5x speedup**. Requires SDR hardware and baseband access. iOS provides neither.
**Research interest only; not implementable on a phone.**

**MDI-LLM.** Model-distributed inference, partitioning a model by layer across
devices. Closest match to the "split a model across iPhones" idea. Practical
bottleneck is the same: per-layer activation transfer over the network.

**The honest conclusion.** Over stock Wi-Fi (realistically 50-200 Mbps), the
per-layer activation traffic will usually make a cluster *slower* than one good
phone. The research results that show large speedups do it over radio with custom
hardware.

Where clustering genuinely wins, and it is a real win: **a model that does not fit
in one phone's RAM.** Three phones at 8 GB can hold a 70B that no single device
can. That is the target use case, and it is about capacity, not speed.

---

## 6. v0.5.1 plan

Phase 0 is done. Phases 1-2 are the cluster. Phases 3+ are opportunistic and
ordered by value per unit of risk.

### Phase 0 - correctness (DONE, pushed, CI green)

- `formatPrompt` now handles a negative return from
  `llama_chat_apply_template`. Previously the growth test `needed >= bufSize` was
  false for a negative, so a failure skipped the retry and the raw prompt went
  out with role prefixes attached. Saturating arithmetic added.
- The result is decoded from an explicit byte count instead of `String(cString:)`,
  which needs a NUL terminator the API does not write.
- Reverted my own wrong "fix": I claimed the `"chatml"` fallback was invalid.
  Checking `src/llama-chat.cpp` shows **54 registered builtin template names and
  `chatml` is one of them**. The original code was correct.

### Phase 1 - RPC-enabled framework (BLOCKED on macOS)

Deliverable: `Scripts/build_rpc_xcframework.sh` + a CI job.

```
cmake -B build-ios-rpc -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DGGML_METAL=ON \
  -DGGML_RPC=ON \
  -DGGML_RPC_RDMA=OFF \
  -DGGML_BLAS_DEFAULT=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_BUILD_TESTS=OFF
```

Gate: the resulting binary must export `ggml_backend_rpc_init`,
`ggml_backend_rpc_start_server`, and `ggml_backend_rpc_get_device_memory`, and
must still export the Metal and `llama_model_load_from_file` controls. A CI
symbol probe identical to the one used to prove RPC was missing.

**Why blocked:** this must be compiled on macOS. I can write the script but cannot
verify it here, and an unverified build script presented as working is exactly
the kind of claim this project has been removing.

### Phase 2 - cluster mode (needs Phase 1)

- **Host mode.** `ggml_backend_rpc_start_server` behind an explicit opt-in toggle,
  default off, local-subnet only. Report the endpoint and a QR code.
- **Join mode.** `ggml_backend_rpc_add_server(endpoint)` per peer.
- **Capacity discovery.** `ggml_backend_rpc_get_device_memory` per peer, then set
  `mparams.tensor_split` from the *measured* proportions. No guessing.
- **Topology UI.** List peers, their free RAM, join/leave, and a live failover
  path when a peer drops mid-generation.
- **Hard cap 16**, from `GGML_RPC_MAX_SERVERS`.

### Phase 3 - parallelism strategy (needs Phase 2)

- **Tensor parallelism** (split each weight matrix) via `tensor_split`. Better
  over high-bandwidth links, more all-reduce traffic.
- **Pipeline parallelism** (split by layer, MDI-LLM style). Less traffic per step,
  more latency per token.
- Select automatically from measured peer bandwidth and RAM. Measure, do not
  assume.

### Phase 4 - desk-scale protocol

One coordinator, N iPhones, USB-C or Wi-Fi. Practical target: run a 70B that no
single phone can hold. Report aggregate capacity and per-peer utilisation.

### Phase 5 - opportunistic / niche (each needs its own feasibility check)

- **Speculative decoding.** A small draft model on the coordinator, verified by
  the large model. Real speedup, no network needed. Best value-per-risk item
  after Phase 0.
- **RDMA over Thunderbolt.** Per Apple TN3205 it exists, but macOS 26.2+ and
  Thunderbolt 5. **No iPhone has Thunderbolt**, so this is macOS-host-only. Keep
  `GGML_RPC_RDMA=OFF` for iOS.
- **RPC local cache** (`-c` flag, `$HOME/.cache/llama.cpp/rpc`). Speeds up
  repeated loads of large tensors.
- **KV cache quantization** across the cluster.
- **AirComp.** Research only. Documented, not implemented.

---

## 7. Status and what I need

**Done and verified:** Phase 0, pushed to `main`, CI green (run 38130323741).

**Blocked:** Phases 1 and 2. Building the RPC XCFramework requires macOS with
Xcode. This environment is Windows. I can write `build_rpc_xcframework.sh` and
the CI job, but I cannot compile or verify them, so I will not claim they work.

**Decision needed from you:**

1. Do you want me to write the Phase 1 build script and CI job for you to run on
   a Mac, clearly labelled as unverified?
2. Or should I implement **speculative decoding** instead, which needs no custom
   framework build, works on a single phone, and is the highest-value item I can
   actually verify from here?
