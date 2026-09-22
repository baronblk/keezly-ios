# Keezly — Device Testing Strategy

Simulators, Xcode Cloud and physical devices each prove something the others
cannot. None of them replaces another (§180).

| Environment | Proves |
|---|---|
| **Simulator** | Rules engine, UI tests, layout matrix, display sizes, OS versions, screenshots, localisation, Dynamic Type, light/dark, Reduce Motion, fast regression |
| **Xcode Cloud** | Reproducible clean-machine build, the official archive, distribution |
| **Physical iPhone** | Real touch, haptics, audio, performance, energy, lifecycle, Game Center, network transitions |
| **Physical iPad** | All of the above plus real ergonomics, board legibility at arm's length, pointer/keyboard, Stage Manager, Split View |

A simulator result is never used to close a device-only bug (§174).

---

## Current availability

Always checked with `scripts/devices.sh` against the live device list, never
assumed from documentation or memory (§157). Availability changes during a
working session — it did on 2026-09-20, when an iPhone appeared after an
earlier check had found nothing — so this section is a snapshot, not a
guarantee. `CURRENT_STATE.md` carries the dated result.

| Role | Present |
|---|---|
| `PRIMARY_IPHONE` | iPhone 17 Pro, iOS 27.0, wired, Developer Mode enabled |
| `PRIMARY_IPAD` | none |

### Reading `devicectl` correctly

`xcrun devicectl list devices` lists **simulators as well as real hardware**,
and a booted simulator reports its state as `connected`. Filtering on connection
state alone will happily mistake a simulator for a device. The only reliable
discriminator is `hardwareProperties.reality`, which is `"physical"` for real
hardware and `"simulated"` otherwise. `scripts/devices.sh` filters on exactly
that.

### What blocks a device run today

Not the hardware — signing. `DEVELOPMENT_TEAM` is unset, and two teams exist in
the keychain. Choosing one belongs to the account owner (MAN-03), and building
would additionally register the device with that team and create a provisioning
profile, which changes an Apple Developer account and needs explicit consent.

### Simulators available

| Runtime | Devices |
|---|---|
| iOS 27.0 | iPhone 18 Pro / 18 Pro Max / 17 / 17e / Air, iPad Pro 13" (M5), iPad Pro 11" (M5), iPad mini (A17 Pro), iPad Air 13"/11" (M4), iPad (A16) |
| iOS 26.5 | iPhone 17 Pro / Pro Max / 17 / 17e / Air, iPad Pro 13"/11" (M5), iPad mini (A17 Pro), iPad Air 13"/11" (M4), iPad (A16) |
| iOS 26.3 | as above plus iPhone 16e, iPad Air 13"/11" (M3) |

---

## Role-based device selection

Scripts and lanes address devices by **role**, never by name or UDID (§158,
§176):

| Role | Used for |
|---|---|
| `PRIMARY_IPHONE` | Touch QA, haptics, audio, performance, lifecycle |
| `SECONDARY_IPHONE` | The second endpoint in Game Center multi-device tests |
| `PRIMARY_IPAD` | Main iPad QA — landscape gameplay, board layout, pointer/keyboard |
| `SECONDARY_IPAD` | Second endpoint, or a different iPad class |

```bash
scripts/devices.sh list                      # human-readable report
scripts/devices.sh roles                     # ROLE=name pairs
scripts/devices.sh udid PRIMARY_IPAD         # UDID, for immediate use
scripts/devices.sh destination PRIMARY_IPAD  # an xcodebuild -destination value
```

Exit codes: `0` found · `3` **BLOCKED / device not available** · `4` tooling
failure. A caller that gets `3` reports BLOCKED. It never reports PASSED (§177).

UDIDs are printed to stdout for immediate use in a command and are never
written into the repository. If a stable local mapping is wanted, put it in
`.keezly-devices.env`, which is git-ignored:

```sh
KEEZLY_PRIMARY_IPAD="My iPad"
KEEZLY_PRIMARY_IPHONE="My iPhone"
```

---

## What runs automatically vs. what needs a human

Anything that can be automated, is (§179). Claude does not ask the user to run
a test by hand when the device is reachable from Xcode.

**Automated:** build · install · launch · XCTest · XCUITest · log capture ·
result-bundle analysis · performance measurement.

**Human judgement required:** visual quality, how the haptics *feel*, ergonomic
reach, whether an animation reads as elegant, and whether the board looks right
on a real iPad at normal viewing distance (§173).

**A person's hands required, which is not the same thing (ISS-019).**
`fastlane device_ipad` runs the app suite on the real iPad — 27 suites green on
2026-09-22 — and then stops at a `Password:` prompt and waits on standard
input. Nothing here will answer it. A credential is the device owner's to type:
it is not recorded in this repository, it does not go into an environment
variable, and no lane will be changed to accept one, because automating past a
credential prompt is the wrong fix even on the runs where it works (§107).

Somebody at the machine running the lane once, interactively, and writing down
*which* credential the prompt belongs to is what unblocks it. Until then the
gate is reported as ATTEMPTED, INCOMPLETE — never as a pass.

---

## Device safety rules

Keezly may be installed, updated, launched, terminated and reinstalled as often
as development requires.

Without an explicit, separate instruction, the following are **never** done
(§165): erasing or resetting a device, removing other apps, broadly changing
device settings, removing Apple accounts, or touching personal data.

---

## iPad checks (§160)

Landscape and portrait gameplay · board size · card legibility · reach to the
hand of cards · touch targets · tap and drag behaviour · animations · haptics
where supported · sound · rotation · Split View and Stage Manager where
supported · mouse and trackpad when paired · external keyboard · Game Center ·
resume from background.

The decisive criterion: **Keezly must never feel like an enlarged iPhone app on
a real iPad.**

## iPhone checks (§161)

Portrait and landscape · card interaction · small touch targets · safe areas ·
Dynamic Island · home indicator · animations · haptics · audio · performance ·
Game Center · network transitions · background/foreground · lock/unlock ·
rotation · state restoration.

---

## Performance on real hardware (§171)

Measured on device, never inferred from the simulator: launch time, input
responsiveness, AI calculation time, board rendering, animation smoothness,
memory footprint, CPU use, energy use, and thermal behaviour during long AI
work.

Hard AI must not heat the device unnecessarily and must never block UI frames.

## Long-run test (§172)

Before release: several complete matches back to back, varying player counts,
with AI, rotation, backgrounding and match restore in between. Looking for
faults that only appear after prolonged use — infinite loops, state corruption,
or steadily growing memory.

---

## Device build requirements (§163)

The project must build cleanly for real hardware at all times: automatic
signing supported, development team configurable, correct bundle identifier and
capabilities, no simulator-only API, no x86 assumptions, no local frameworks
lacking a device slice.

A feature that compiles for the simulator but fails a device build is **not**
tested.

---

## Reporting

Test status is recorded per environment and never merged (§167):

```
Simulator      : …
Xcode Cloud    : …
Physical iPhone: …
Physical iPad  : …
```

Results go into `CURRENT_STATE.md` → Device Verification. Device-only defects
are marked as such in `KNOWN_ISSUES.md`, including whether they reproduce in
the simulator.
