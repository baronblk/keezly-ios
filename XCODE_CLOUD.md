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

## Archive — why build 33 failed, and the one thing it needs

**Status: ARCHIVE NOT VERIFIED.** Release build 33 ran Test ✅, Analyze ✅ and
Archive ❌.

The chain, read from Apple's own distribution logs rather than guessed:

```
1. Archive built:  CONFIGURATION Release          ← correct
2. CodeSign:       Signing Identity "Sign to Run Locally"
                   codesign --force --sign -      ← ad-hoc, no team
3. Analyze:        isAdHocSigned='1', teamID='(null)',
                   no embedded.mobileprovision
4. Export:         "Xcode couldn't find any iOS App Store provisioning
                   profiles matching 'de.gcng.keezly'"
5. Repair:         Xcode tries to mint one, which needs an authenticated
                   App Store Connect session
6. Failure:        "Unable to authenticate with App Store Connect
                   (Session Proxy Provider)"
```

**Step 6 is a symptom, not the cause.** It is worth saying plainly because the
message invites the wrong fix: it looks like an account or agreements problem,
and it is not. Nothing was wrong with the account — the entitlement resolved,
`GAME_CENTER` was present in the app ID features, the team `KZFCCDV6A8` was
found, and a profile was issued at 07:19:31 with `errors: (null)`.

**The cause is step 2.** `DEVELOPMENT_TEAM` lives in `Config/Local.xcconfig`,
which is git-ignored and exists only on a developer's Mac. Xcode Cloud has no
such file, automatic signing had no team to resolve, and the archive came out
ad-hoc. Everything after that is Xcode trying to rescue an archive that was
never signed for distribution.

### The fix, and the single owner action

`ci_post_clone.sh` now writes `Config/Local.xcconfig` from
`KEEZLY_DEVELOPMENT_TEAM`. The repository still contains no team id (§106,
§158) — a team id is not a credential, it is in every shipped app, but the rule
stands and an environment variable costs one setting.

**OWNER ACTION:** App Store Connect → Xcode Cloud → *Keezly Release* → Environment
→ add `KEEZLY_DEVELOPMENT_TEAM = KZFCCDV6A8`.

That value is Apple's own, taken from the export log of build 33. Add it to CI
and Main too if those should ever archive; they currently do not.

Without the variable nothing breaks: a simulator build and a test run need no
team, so it is absent by design and the script says so on an archive instead of
failing silently.

### What is still unknown

Whether the upload succeeds once the archive is properly signed. The
authentication error should disappear with it, because Xcode will no longer be
trying to repair provisioning — but that is a prediction, and it is not
verified until a Release build reaches TestFlight. **Do not treat agreements as
the problem until a properly signed archive has failed.**

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
