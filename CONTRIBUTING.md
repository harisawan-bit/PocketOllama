# Contributing

Thanks for looking at PocketOllama. This document covers the conventions that
are not obvious from reading the code.

## Reporting a bug

Please include, and do not skip any of these. A report missing one of them
usually cannot be acted on:

1. **Device and chip.** Settings shows the GPU name; the SoC is in the device
   table. "iPhone" alone is not enough, because behaviour differs a lot
   between a 2 GB A11 and an 8 GB A19.
2. **iOS version.**
3. **Model file**, including quantisation, and its size.
4. **What you did**, and what happened instead.
5. **Whether it is reproducible** after a full app restart.

For anything memory-related, note whether the device has other heavy apps
open. iOS jetsams a process well before physical RAM runs out, and what is
resident changes the outcome.

## Ground rules for code changes

**No fake capability claims.** This is the rule the project cares most about.
Do not claim hardware the app does not use, do not invent benchmark numbers,
and do not describe a setting as functional when nothing reads it. Several
such claims existed and were removed; they are the reason this rule is first.

**Every user-visible setting must do something.** If a toggle or slider does
not change behaviour, either wire it up or delete it. Dead settings were a
recurring bug here.

**One implementation, not three.** Logic that needs testing goes in a
dependency-free file that `Scripts/LogicSelfCheck.swift` can compile and run.
Do not copy logic into the test; a copy passes while the real code breaks.
That happened, and the test reported success through a real regression.

**A check must be able to fail.** If you add a gate, break the thing it guards
and confirm the gate goes red. Several gates here were added after an `exit`
and never ran.

## Adding a device

1. Find the `hw.machine` identifier. AppleDB lists them per model along with
   the SoC, which is what to trust; do not guess from the marketing name.
2. Add one row to `deviceTable` in `PocketOllama/Core/HardwareAutoTuner.swift`.
   A row is `identifiers`, `soc`, `name`, `context`, `kv`, `tier`, `is8GBPlus`,
   `speculative`, `fallbackThreads`.
3. Pick the context from the device's RAM, not from the chip name. The KV
   cache scales with the model's real dimensions, and the post-load check
   will refuse a context that does not fit.
4. Keep the table sorted newest first. The first match wins.
5. Verify the SoC against AppleDB before committing.

## Building

```bash
./Scripts/fetch_llama.sh      # downloads the pinned xcframework
xcodegen generate
xcodebuild build -project PocketOllama.xcodeproj -scheme PocketOllama \
  -destination "generic/platform=iOS" -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

There is no committed `.xcodeproj`; it is generated from `project.yml`.
Edit `project.yml`, never a generated file.

`Scripts/verify_no_stubs.sh` rejects canned output, fake token pacing, and
hardcoded capability claims. `Scripts/LogicSelfCheck.swift` runs the logic
tests. Both run in CI and both must pass.

## Cutting a release

Set `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`, then
tag and push. CI builds, verifies, and attaches the IPA to the release.

Keep the build number non-decreasing. iOS refuses to install an IPA whose
build number is lower than what is already on the device, so a reset of the
marketing version needs a high build number to be installable.

## Before opening a PR

- [ ] `Scripts/verify_no_stubs.sh` passes locally
- [ ] The self-check passes in CI
- [ ] No setting was added that does nothing
- [ ] No capability is claimed that was not measured
- [ ] `CHANGELOG.md` has an entry
- [ ] If the device table changed, the SoC was verified against AppleDB
