---
name: Bug report
about: Something crashed, failed, or behaved differently than described
title: ''
labels: bug
assignees: ''
---

**Describe the bug**
A clear description of what happened.

**To reproduce**
Steps to make it happen again.

**Expected behaviour**
What you expected instead.

**Device and iOS version (required)**

| Field | Value |
|---|---|
| Device | e.g. iPhone 15 Pro |
| Chip | Settings shows the GPU name, e.g. Apple A17 Pro |
| iOS version | e.g. 18.1 |
| App version | Settings, or the release tag you installed |

**Model (required for inference problems)**

| Field | Value |
|---|---|
| Model file | e.g. qwen2.5-0.5b-instruct-q4_k_m.gguf |
| Size | e.g. 390 MB |
| Quantisation | e.g. Q4_K_M |

**Context settings (for memory, crash, or slow-response reports)**

| Field | Value |
|---|---|
| Context window | tokens |
| KV quantisation | |
| Thread count | |
| GPU offload | all layers |

**Screenshots or logs**
If it crashed, the Xcode device log or the crash report. The in-app log on the
Dashboard shows recent requests.

**Other apps open**
For anything memory related, iOS jetsams a process well before physical RAM
runs out. Note whether you had heavy apps in the background.

**Reproducible after a full app restart?**
Yes / No.

**Additional context**
Anything else.
