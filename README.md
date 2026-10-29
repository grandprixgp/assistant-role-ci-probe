# assistant-role-ci-probe

Settle the **software half** of the Android assistant-role question in emulated CI.

## Intent

This repository exists to answer one question reproducibly in GitHub Actions, on an
emulated Android device, without any physical hardware:

> Can the `android.app.role.ASSISTANT` role be granted to a package, and can
> `KEYCODE_ASSIST` / `KEYCODE_VOICE_ASSIST` be dispatched to that role holder,
> on a stock AOSP image?

It is deliberately a *software-only* probe. It does **not** prove anything about
the physical Side button, firmware, or OEM-specific assist handling. Those remain
out of scope and are not claimed anywhere in this repo's outputs.

## Emulator image used

| Field | Value |
|---|---|
| Action | `reactivecircus/android-emulator-runner@v2` |
| `api-level` | `34` (fallback `30` if the API 34 default image is unavailable) |
| `target` | `default` (AOSP / non-Google image) |
| `arch` | `x86_64` |
| `script` | see `.github/workflows/emulator.yml` |
| KVM | enabled via `-enable-kvm` (ubuntu-latest runners support nested virt) |
| GPU | `swiftshader_indirect` |

### Why a non-Google image (`target: default`)?

The assistant-role question is about the **platform** behavior of `RoleManager` /
`cmd role`, not about Google Assistant or Google Play Services. A `google_apis` /
`google_apis_playstore` image would (a) pull in Google's own assistant handling,
(b) require accepting Google Terms / licensing in CI, and (c) make results
non-reproducible across forks. The `default` (AOSP) image keeps the probe
measuring stock platform behavior, fork-safe and secret-free.

## Scope boundary

- **In scope:** software role grant via `cmd role add-role-holder`, role-holder
  query via `cmd role get-role-holders`, and assist-key dispatch via
  `input keyevent KEYCODE_ASSIST` / `KEYCODE_VOICE_ASSIST` as a software proxy.
- **Out of scope:** the physical Side button, firmware, and any OEM-specific
  assist routing. `input keyevent` is a software proxy only.

## Files

- `.github/workflows/emulator.yml` — CI workflow that boots the emulator and runs the probe.
- `probe/assistant_role_probe.sh` — probe script (sibling task).
- `docs/t-0118-verdict.md` — software-half verdict (sibling task).

## Reproduce

Trigger the workflow manually:

```
gh workflow run emulator.yml --repo grandprixgp/assistant-role-ci-probe
```

Or push to `main`. No secrets are required; the repo is public and fork-safe.
