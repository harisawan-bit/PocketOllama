<!--
  PocketOllama is a local inference server. Anything that reduces what it can
  do on the phone also reduces what a PR should be allowed to claim. Please
  read CONTRIBUTING.md before opening a PR.
-->

## What this changes

<!-- One paragraph. What changes for a user, not what changed in the diff. -->

## Why

<!-- The problem, or the issue this closes. -->

## Verification

<!-- What you actually ran, and what it printed. "Builds clean" is not enough. -->

| Check | Result |
|---|---|
| `Scripts/verify_no_stubs.sh` | |
| Self-check in CI | run id / link |
| Build on device (if applicable) | device, chip, iOS version |

## Checklist

- [ ] No capability is claimed that was not measured on a real device
- [ ] No setting was added that does nothing
- [ ] No fake benchmark numbers, no invented token rates
- [ ] Shared logic lives in a file the self-check can compile, not a copy
- [ ] Any new gate in `Scripts/verify_no_stubs.sh` was verified to fail when
      the thing it guards is broken
- [ ] If the device table changed, every SoC was verified against AppleDB
- [ ] `CHANGELOG.md` has an entry
- [ ] `README.md` updated if user-facing behaviour changed

## Risk

<!-- What could break. Anything touching memory, downloads, or the server is
     worth calling out explicitly, because those are where the data loss and
     crash bugs were. -->
