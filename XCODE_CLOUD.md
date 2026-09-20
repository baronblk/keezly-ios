# Keezly — Xcode Cloud

**Status: NOT PREPARED, NOT CONFIGURED, NOT VERIFIED.**

The three states are kept strictly apart (§117):

| State | Meaning | Keezly |
|---|---|---|
| PREPARED | `ci_scripts/`, shared scheme and a buildable project exist in the repo | **No** |
| CONFIGURED | The workflow exists in Xcode / App Store Connect | **No** |
| VERIFIED | A real Xcode Cloud build has run and passed | **No** |

No claim of "Xcode Cloud is set up" will be made on the basis of local files
alone. Manual steps are listed in `docs/XCODE_CLOUD_SETUP_CHECKLIST.md` (to be
written with M0.4) and tracked in `CURRENT_STATE.md` → Manual Actions.

Tracked as M11.1–M11.3 in `ROADMAP.md`.

---

## Prerequisites still missing

1. An Xcode project with a **shared** `Keezly` scheme (M0.2 — does not exist).
2. `ci_scripts/` (M0.4 — does not exist).
3. GitHub ↔ Xcode Cloud authorisation (MAN-04 — manual, OPEN).
4. An App Store Connect app record (MAN-02 — manual, OPEN).

Until 1 and 2 exist there is nothing for Xcode Cloud to build, so the §119 goal
of a green cloud build right after M1 cannot be met yet. That is stated rather
than worked around.

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
