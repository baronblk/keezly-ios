# Keezly — fastlane

**Status: RUN.** fastlane 2.240.1 runs through Bundler, and the lanes below
are recorded with what happened when they were actually executed rather than
with what they are expected to do.

## Toolchain

Ruby is pinned to **3.4.10** in `.tool-versions` and `.ruby-version`, which
`mise`, `asdf` and `rbenv` all read. fastlane's own version is fixed by the
committed `Gemfile.lock` (DEC-012).

It was pinned to 4.0.5, and on 4.0.5 **not one lane runs**: fastlane 2.240
raises a `NameError` inside its own CLI dispatcher before it reaches a
lane. The pin had been chosen because Homebrew's `ruby` happened to provide
that version, and the documentation said the lanes worked — which nobody had
checked, because checking it would have produced that error immediately.
Raise the pin when fastlane supports the next Ruby, not when a package
manager does.

First time on a machine:

```bash
bundle config set --local path vendor/bundle
bundle install
```

fastlane is always invoked through Bundler:

```bash
bundle exec fastlane <lane>
```

A globally installed fastlane is a convenience, never a project requirement
(§83).

---

## Planned files

```
Gemfile
Gemfile.lock          committed, so the fastlane version is reproducible
fastlane/
  Appfile
  Fastfile
  Snapfile
  metadata/           App Store metadata per locale
  screenshots/        de-DE, nl-NL, en-US
  README.md
```

---

## Planned lanes (§84, §122)

| Lane | Purpose | Status |
|---|---|---|
| `tests` | Rules engine (`swift test`) plus app-level tests on an iPhone simulator | working |
| `ui_tests` | XCUITests on an iPhone and an iPad simulator | working |
| `qa` | The whole local quality gate: engine tests, build, unit tests, UI tests | working |
| `release_check` | Release-candidate gate, reporting each sub-gate separately | working |
| `asc_check` | Verify App Store Connect credentials and whether the app record exists | working |
| `device_smoke` / `device_iphone` / `device_ipad` / `device_gate` | Physical-device gates, resolved by role | working |
| `screenshots` | The complete App Store screenshot matrix | M11.5 |
| `screenshots_verify` | Verify completeness and emit an HTML preview | M11.5 |

`release_check` currently verifies the version, a clean git tree, the absence
of tracked secret-like files, a real app icon, and the engine test suite. As
localisations, store metadata and screenshots land, their checks are added
there too.

`release_check` reports each gate separately and never collapses them (§178):

```
Simulator Gate              : PASS / FAIL
Physical iPhone Gate        : PASS / FAIL / BLOCKED
Physical iPad Gate          : PASS / FAIL / BLOCKED
Game Center Real Device Gate: PASS / FAIL / BLOCKED
```

A final App Store release candidate may not leave a mandatory real-device gate
at `BLOCKED`.

### Device lanes (§177)

| Lane | Purpose |
|---|---|
| `device_smoke` | Build, install and launch on whichever physical device is available |
| `device_iphone` | The physical-iPhone gate: XCUITests on `PRIMARY_IPHONE` |
| `device_ipad` | The physical-iPad gate: XCUITests on `PRIMARY_IPAD` |
| `device_gate` | Both of the above plus the long-run test |

Each device lane resolves its target through `scripts/devices.sh`, which
addresses devices by **role**, never by name or UDID (§158, §176). Every lane
checks availability first. If no suitable device is connected, the lane reports
**`BLOCKED / DEVICE NOT AVAILABLE`** and exits non-zero. It never reports
`PASSED` for a test it did not run (§177).

No other commands. Nothing magic and undocumented.

---

## Interim state

Until `tests` exists, the equivalent command is:

```bash
cd Packages/KeezlyCore && swift test
```

which currently runs 57 tests including 221 complete randomised matches.

---

## What fastlane must not do

- Not produce a second archive when Xcode Cloud already archives (§85).
- Not upload the same build to TestFlight in parallel with Xcode Cloud.
- Not require any credential to be present in the repository. App Store Connect
  access uses an API key held **outside** the repository, configured through the
  environment (§107).
