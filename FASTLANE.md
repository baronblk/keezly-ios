# Keezly — fastlane

**Status: NOT STARTED.** There is no `Gemfile` and no `fastlane/` content yet.
None of the commands below work today. They are the agreed target so that the
lane names do not drift.

Tracked as M0.3 and M11.5/M11.6 in `ROADMAP.md`. See also `CI_CD.md`.

---

## Blocking decision

System Ruby on this machine is **2.6.10**, which is too old for a modern
Bundler-based fastlane. Homebrew `ruby@4.0` and `mise` are both available. The
toolchain choice must be made before M0.3 starts, and recorded in
`DECISIONS.md`.

fastlane is always invoked through Bundler once it exists:

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

| Lane | Purpose |
|---|---|
| `tests` | Full unit and integration tests — rules engine, AI, persistence |
| `ui_tests` | XCUITests on iPhone and iPad |
| `screenshots` | The complete App Store screenshot matrix |
| `screenshots_verify` | Run screenshots, verify completeness and correctness, emit an HTML preview |
| `qa` | The whole local quality gate: build, unit, integration, relevant UI tests, static checks, engine simulation, screenshot smoke test |
| `release_check` | Release-candidate gate: version, build number, clean git tree, tests, app icon, localisations, store metadata, screenshot completeness, release configuration, no debug code, no secrets |

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
