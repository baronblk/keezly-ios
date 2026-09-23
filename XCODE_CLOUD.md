# Keezly — Xcode Cloud

**Status: PREPARED and CONFIGURED. NOT VERIFIED.**

The three states are kept strictly apart (§117):

| State | Meaning | Keezly |
|---|---|---|
| PREPARED | `ci_scripts/`, shared scheme and a buildable project exist in the repo | **Yes** |
| CONFIGURED | The workflow exists in Xcode / App Store Connect | **Yes** — owner initialised it 2026-09-23 |
| VERIFIED | A real Xcode Cloud build has run and passed | **No** |

No claim of "Xcode Cloud is set up" is made on the basis of local files alone,
and none is made on the basis of a workflow existing either. VERIFIED means a
cloud build ran and passed, and that has not happened.

---

## The shared scheme — VERIFIED FROM A CLEAN CLONE

Xcode Cloud warned:

> The scheme 'Keezly' may only exist locally. To use it in this workflow, it
> must be pushed to your repository.

**The repository does not have that problem, and did not have it.** Checked
rather than assumed, by cloning `origin/main` into an empty directory and asking
`xcodebuild` what it could see there:

```
Keezly.xcodeproj/xcshareddata/xcschemes/Keezly.xcscheme    tracked
xcuserdata                                                  absent, everywhere
xcodebuild -project Keezly.xcodeproj -list  ->  Schemes: Keezly, KeezlyCore
```

The scheme has been at that path since `711cb93`, the commit that first added
the project. It has never lived under `xcuserdata`; `.gitignore` excludes
`xcuserdata/` and `*.xcuserdatad/` and nothing else near it.

### What was actually wrong locally

One thing, and it was not the scheme. Opening the project in Xcode rewrote
`project.pbxproj` — adding `lastKnownFileType` to nineteen file references —
so the working tree's project file no longer matched the pushed one. Xcode
compares the project on disk against the repository, and a project file that
differs from what was pushed is a reason for it to be unsure about what the
remote contains.

That is repaired the only correct way for this project: **regenerate from the
canonical definition**. `project.yml` is the source of truth; the `.xcodeproj`
is an output that happens to be committed. After `xcodegen generate` the
`.pbxproj` and the scheme are byte-identical to what is already on `main`.

**Never hand-edit the generated project to satisfy a warning.** The next
regeneration discards it and the warning returns with no record of why.

### The scheme's four actions

Declared in `project.yml` → `schemes.Keezly`, so they survive regeneration:

| Action | Configuration | Targets |
|---|---|---|
| Build | — | `Keezly` (all), `KeezlyTests` (test), `KeezlyUITests` (test) |
| Test | Debug | `KeezlyTests`, `KeezlyUITests`, coverage on `Keezly` |
| Analyze | Debug | `Keezly` |
| Archive | **Release** | `Keezly`, reveals in Organizer |

### Archive works — proven, not assumed

Run from the clean clone, not from this working copy:

```bash
xcodebuild -project Keezly.xcodeproj -scheme Keezly \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/Keezly.xcarchive archive
```

```
** ARCHIVE SUCCEEDED **
Products/Applications/Keezly.app
  CFBundleIdentifier         de.gcng.keezly
  CFBundleShortVersionString 1.0.0
  CFBundleVersion            1
  CFBundleSupportedPlatforms iPhoneOS
  UIDeviceFamily             1, 2        (iPhone and iPad)
```

Signing was disabled for the proof, because `DEVELOPMENT_TEAM` is deliberately
absent from `project.yml` — it is developer-specific and does not belong in the
repository. Xcode Cloud supplies signing itself. What this proves is that the
scheme's archive action is correctly wired to the app target in Release; it does
not prove a signed build, and is not offered as proof of one.

### The product manifest

`Keezly.xcodeproj/xcshareddata/xcodecloud/manifest.json` is written by Xcode
Cloud and is now tracked: a product id, a target id and a target name. No
credential, no team id. XcodeGen leaves it alone on regenerate, which was
checked rather than assumed.

---

## Archive — verified. Upload — not.

Three states, kept strictly apart because they are not the same thing:

| | |
|---|---|
| **CLOUD ARCHIVE** | **VERIFIED** — build 37 |
| **DISTRIBUTION SIGNING** | **VERIFIED** — build 37 |
| **TESTFLIGHT UPLOAD** | **NOT VERIFIED** — no build has ever reached App Store Connect |

### What was verified, from the artefact rather than the status

The App Store export was downloaded from Apple and the `.ipa` opened:

```
CONFIGURATION Release
CFBundleIdentifier          de.gcng.keezly
CFBundleShortVersionString  1.0.0
CFBundleVersion             37          ← from CI_BUILD_NUMBER, monotonic
CFBundleSupportedPlatforms  iPhoneOS
UIDeviceFamily              1, 2        ← iPhone and iPad
PrivacyInfo.xcprivacy       present

Authority       Apple Distribution: RENÉ SUESS (KZFCCDV6A8)
TeamIdentifier  KZFCCDV6A8
CodeDirectory   flags=0x0(none)         ← not 0x2(adhoc)
Profile         iOS Team Store Provisioning Profile: de.gcng.keezly
                get-task-allow = false
Entitlements    application-identifier      KZFCCDV6A8.de.gcng.keezly
                com.apple.developer.team-identifier KZFCCDV6A8
                com.apple.developer.game-center

** EXPORT SUCCEEDED **   app-store, development and ad-hoc
```

### The one thing that fails, and two wrong diagnoses before it

```
App Store Connect request for store configuration failed for account
Session Proxy Provider: Unable to authenticate with App Store Connect
```

Identical in builds 33 and 37. The archive is built, signed for distribution and
exported; Xcode Cloud cannot authenticate to hand it over.

**Two diagnoses of this were wrong and are written down so they are not made
again.**

1. *"Agreements are probably the cause."* Offered before reading the logs.
2. *"No — the missing DEVELOPMENT_TEAM is the cause, agreements are fine."*
   Offered after reading them, and also wrong. `Sign to Run Locally` at archive
   time is not a fault: Xcode Cloud archives unsigned and signs at **export**.
   Build 37 had the team and signed identically at archive time, and exported
   perfectly.

The environment variable mechanism was built on the second wrong diagnosis. It
is harmless and arguably correct anyway — a project that can be archived on a
developer's Mac should be archivable in the cloud — but it did not fix this, and
it should not be recorded as having done so.

**What is actually left is account-level**: the Xcode Cloud ↔ App Store Connect
authorisation, or the agreements that gate it (Paid Applications, for a paid
app). Neither is readable through the API with the key this project holds, and
neither is a thing to change on suspicion.

**OWNER ACTION:** App Store Connect → Business → Agreements, Tax and Banking.
Confirm the Paid Applications agreement is active and nothing is awaiting
acceptance. Then re-run *Keezly Release*; everything before the upload already
works.

---

## Planned workflows

### Keezly CI — pull requests and development branches

Actions: **build**, **test**.
Test targets: rules engine, AI, persistence, key integration tests, plus one
representative iPhone and one representative iPad destination.
Must stay fast enough to run on every push. No full screenshot matrix here.

### Keezly Main — merges to `main`

Actions: **build**, **test**, **analyze**, and **archive** once the project is
far enough along.
Wider than CI: full engine suite, simulation, persistence, relevant UI tests on
both iPhone and iPad.

### Keezly Release — deliberate trigger or release tag

Actions: **build**, **test**, **analyze**, **archive**, then TestFlight
distribution. Only a fully green run may be archived and distributed. Not run
per commit.

### Keezly Nightly — optional, scheduled

Large AI simulation, extended tests, extra devices, serialisation compatibility,
replay, additional seeds. To be prepared and documented before it is switched
on, so it does not burn quota from day one (§113).

---

## `ci_scripts/` (planned)

```
ci_scripts/
  ci_post_clone.sh       toolchain check, Ruby/Bundler deps if needed, version logging
  ci_pre_xcodebuild.sh   build-number derivation, generated config
  ci_post_xcodebuild.sh  artifact collection, result reporting
```

Every script: executable, correct shebang, robust, idempotent, and logging what
it does. Complex steps move into helper scripts rather than growing one large
shell file (§102).

Before writing `ci_post_clone.sh`, check which Ruby and Bundler versions the
current Xcode Cloud image actually ships. Outdated tutorials will not be copied
blindly (§103).

---

## Environment variables

Only official Xcode Cloud variables are used (§104): `CI`, `CI_XCODE_CLOUD`,
`CI_BUILD_ID`, `CI_BUILD_NUMBER`, `CI_WORKFLOW`, `CI_XCODE_SCHEME`,
`CI_XCODEBUILD_ACTION`, `CI_XCODEBUILD_EXIT_CODE`. No heuristic detection of
"are we in CI".

---

## Versioning

`MARKETING_VERSION` stays at `1.0.0` until a deliberate product version change.
`CFBundleVersion` derives from `CI_BUILD_NUMBER` where available, so it is
monotonic and App Store compatible. Build numbers are never improvised from the
local clock when a stable CI number exists (§105).

---

## Secrets

Never in git, the `Fastfile`, the `Appfile`, shell scripts, `xcconfig` files,
plists or documentation. Only Xcode Cloud environment secrets, App Store Connect
mechanisms, or local untracked environment configuration (§106). `.gitignore`
already blocks `*.p8`, `*.p12`, `*.mobileprovision`, `AuthKey_*`, `.env` and
friends.
