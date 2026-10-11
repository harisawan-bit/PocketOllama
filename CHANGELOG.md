# Changelog

All notable changes to PocketOllama. Dates are the release dates of the tag.

The version number was reset to **0.5** on 2026-10-11 at the maintainer's
request. Releases `v2.2.0` through `v3.1.1` are superseded by `v0.5`, which
contains all of their fixes. The build number jumped to 100 so the new
version installs over the old ones, since iOS refuses an install whose
`CFBundleVersion` is lower than what is already present.

## [0.5] - 2026-10-11

Version reset to 0.5 (build 100). All fixes below are new in this release.

### Device support

- The hardware table covered 11 identifiers across four chip families. Every
  iPhone that can run iOS 16.4 now has an entry: 45 identifiers from the A11
  through the A20 Pro, each verified against AppleDB's per-model SoC field.
- `iPhone17,5` was listed with the 16 and 16 Plus as an A18. It is the 16e,
  a cheaper part, and was being handed the 8B model tier.
- The iPhone 17 family (`iPhone18,x`) and the 18 family (`iPhone19,x`) were
  absent and fell through to the fallback.
- The fallback for unknown devices had a single 7.2 GB cut-off, so a 2 GB
  phone and a 6 GB phone were both recommended a 3B model at an 8k context.
  It is now five measured-RAM bands.
- A11 through A15 parts do not expose the `hw.perflevel0` sysctl, so core
  detection returned the total logical count and would have scheduled
  inference on efficiency cores. Those chips are 2 performance cores plus 4
  efficiency cores, so 2 is now used.
- Thread count was hardcoded to 2 for every device and the app never asked
  the OS. It now reads the performance-core cluster.

### Crashes

- Switching tabs mid-generation crashed the app. `onDisappear` clears the
  message array while the stream is still writing into it, so a token already
  in flight indexed an empty array.
- A remote, unauthenticated crash: the chunked-encoding decoder added a
  client-supplied chunk size to a cursor without checking for overflow, which
  traps in Swift. This was reachable before the API key check.
- The 64-byte token buffer was allocated on every single token, and a second
  array per token converted it to bytes.

### Memory

- `os_proc_available_memory` returns 0 when the process has exceeded its
  memory limit, which Apple documents. That 0 was compared directly in the
  post-load check, so the model loaded, was freed again, and every load
  failed as "not enough free memory" on a healthy idle phone.
- A device reporting between 6.5 and 8 GB was handed the 8B tier and a 32k
  context. A 4.9 GB weights file leaves no room for that on 6 GB.
- The "memory balloon" allocated 64 MB, advised it away, and freed it while
  claiming to signal Darwin compaction. It reclaimed nothing and spiked usage
  in the one path where memory is scarce. Removed.

### Leaks

- Every inference request leaked its Task. `onTermination` captured the
  producer, whose body held the continuation, which held `onTermination`.

### Security

- Model output was assigned to `innerHTML` in the web dashboard. The model is
  untrusted and the API key lives in `localStorage` in the same origin, so
  markup in a response could run script and read the key.
- The API key is never embedded in served HTML. The local user types it and
  it is kept in the browser.

### Downloads

- Nothing checked free disk space. A 4.92 GB download against a nearly full
  device failed late, after the space was gone.
- A completed download was not verified to be a GGUF file, so an HTTP 200
  carrying an HTML error page was saved as `<model>.gguf` and failed much
  later at load.
- iOS relaunches the app to finish a large background download. In the fresh
  process the task mapping was empty, so the finished file was discarded.
- `modelId` became a filename unchecked.

### Performance

- `offload_kqv` and `op_offload` were never set, leaving the KV cache and
  host tensor ops on whatever the library default was. The KV cache now stays
  resident on the Metal device instead of being copied back per token.
- `n_gpu_layers` is -1, the library's own "all layers".
- `full + piece` built a fresh full-length string per token, which is
  quadratic over a long answer.
- Prefill submitted a hardcoded 512-token chunk regardless of the configured
  batch, so the prefill-batch setting did nothing.
- `n_ubatch` could exceed `n_batch`, which makes context creation fail. One
  shared clamp now governs both, tested for every selectable value.

### Correctness

- Safe context was computed from RAM alone and ignored the model's trained
  context length, so a model trained at 8k could be handed 64k.
- KV-cache arithmetic existed in three places, one of which used the wrong
  `head_dim` under grouped-query attention. One implementation now, tested.
- The SSE reader split each network read on newlines with no carry-over, so a
  `data:` line arriving in two pieces was dropped by a silent catch.
- `TextDecoder` ran without streaming, corrupting multi-byte characters split
  across reads.
- Every engine error rendered as an empty string. Each case now carries a
  message.
- A concurrent request returned 500 instead of 503, telling clients not to
  retry something that succeeds seconds later.
- `/api/version` returned a hardcoded `0.1.48`.
- The log recorded a client IP and never displayed it, and the value was a
  debug rendering rather than an address.
- The thread slider did nothing above the detected core count, because the
  thermal governor's base was never updated.
- The context slider's minimum was above the safe maximum on low-RAM bands.
- The model store advertised context figures the budget code would refuse.

### Tests

`Scripts/LogicSelfCheck.swift` compiles the real production helpers and runs
95 assertions over them, so a change that breaks the logic fails CI rather
than shipping. It covers prompt compaction, context sizing, RAM bands, KV
arithmetic, GGUF magic validation, path safety, HTTP framing, size parsing,
and stop-sequence matching.

---

## [3.1.1] - 2026-09-28

- A remote crash from an unchecked chunk-size addition in the chunked decoder.
- The model store stopped advertising context it would refuse, and free disk
  space is now checked before a multi-gigabyte download.
- Dead budget code removed: a KV recommendation that ignored model size, and
  a string-based prompt compactor that duplicated the real token-based one.
- Request logging now reports the real client address.

## [3.1.0] - 2026-09-28

- Unknown devices stopped being reported as "A17 Pro / M-Series" with invented
  core counts. Limits are derived from measured RAM.
- Safe context is capped at the model's trained length.
- KV quantisation is chosen per model instead of from the device table.
- Completing a model download no longer overwrites a context the user set.
- KV arithmetic consolidated from three copies into one.

## [3.0.0] - 2026-10-11

- Full GPU offload: `offload_kqv`, `op_offload`, `n_gpu_layers = -1`, with
  `split_mode` and `main_gpu` explicit.
- Thread count from the real performance cores instead of a hardcoded 2.
- Fixed a load-fatal bug where selecting prefill batch 512 produced
  `n_ubatch` above `n_batch`.
- Removed the false "35 TOPS ANE" claim. The Neural Engine is not used.

## [2.7.0] - 2026-09-28

- `isIdleTimerDisabled` is restored rather than left set, so the screen locks
  again after nightstand mode.
- The silent audio background mode was removed. It ducked the user's music
  for a feature iOS never granted.
- The last loaded model is persisted, so the correct model is restored.
- A generation can now be stopped.
- The QR sheet displays the hostname.

## [2.6.0] - 2026-09-28

- Prompt compaction stopped injecting an unknown token.
- Telemetry split prefill and decode timing.
- Downloads report real errors and can be retried.
- Bonjour publication reports failures instead of failing silently.

## [2.5.0] - 2026-09-27

- API key parsing reads HTTP headers, not the request line.
- Completion tokens are counted on stop-token exits.
- Front truncation replaced with middle-out compaction.
- GGUF context and grouped-query head dimensions parsed correctly.
- Mid-stream failures propagate as explicit SSE errors.

## [2.4.0] - 2026-09-27

- The last loaded model is restored on launch.
- `/v1/models` lists real files on disk with real sizes.
- The context slider reloads the model.
- Optional API key protection for inference routes.

## [2.3.0] - 2026-09-27

- Playground no longer double-wraps prompts, reports real errors, and is
  disabled until a model is loaded.

## [2.2.4] and earlier - 2026-09-27

- Replaced the simulated inference engine with real llama.cpp inference.
- Real binary GGUF metadata parsing.
- Real resumable-capable downloads with progress and validation.
- The old releases produced an IPA with no llama.cpp in it.
