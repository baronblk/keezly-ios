# Keezly — CI/CD

**Status: NOT STARTED.** No CI exists. The only reproducible command today is:

```bash
cd Packages/KeezlyCore && swift test
```

Tracked as M0.3/M0.4 and M11 in `ROADMAP.md`. Companion documents:
`FASTLANE.md`, `XCODE_CLOUD.md`, `docs/SCREENSHOTS.md`.

---

## Responsibility split

CI/CD is part of the architecture, not a release-time afterthought (§81).
Two systems, clearly divided (DEC-008):

| System | Owns |
|---|---|
| **GitHub** | Source of truth for code and history |
| **Xcode Cloud** | Official build, test, analyze, archive, signing, TestFlight |
| **fastlane** | Local test lanes, screenshot pipeline, metadata, QA and release gate |
| **XCTest / Swift Testing / XCUITest** | The tests themselves |

They must not duplicate each other. fastlane does **not** produce a second
archive or a parallel TestFlight upload of a build Xcode Cloud already made.

No GitHub Actions workflow will be added for the same Apple builds unless a
concrete technical reason appears (§82).

A developer must be able to build, test, screenshot and QA Keezly entirely
locally, without Xcode Cloud (§124).

---

## Target pipeline

```
Developer
   └─ git commit ─▶ GitHub
                      └─ Xcode Cloud: build + test + analyze
                            └─ main green
                                  └─ release candidate
                                        ├─ bundle exec fastlane release_check   (local gate)
                                        ├─ bundle exec fastlane screenshots     (local)
                                        ├─ screenshot review
                                        └─ Xcode Cloud "Keezly Release"
                                              └─ archive ─▶ TestFlight ─▶ App Store review
```

A release candidate is only releasable when **both** the local
`fastlane release_check` and the Xcode Cloud release workflow are green (§114).

---

## Test matrix (planned)

Not every combination on every build (§111).

| Trigger | Scope |
|---|---|
| Pull request | Full rules engine; one representative iPhone; one representative iPad |
| Merge to `main` | Full engine + integration; several form factors; portrait and landscape |
| Release | Smallest supported iPhone, current iPhone, large iPhone, iPad mini, iPad 11", iPad 13" |
| Nightly (optional) | Large AI simulation, serialisation compatibility, replay, extra seeds |

## Cloud versus local devices

Xcode Cloud uses Apple's hosted infrastructure and its configured destinations.
The development Mac uses the physical devices actually paired with it. These are
different things and their results are recorded separately (§167):

```
Simulator      : …
Xcode Cloud    : …
Physical iPhone: …
Physical iPad  : …
```

It is never claimed that a locally paired device was tested "by Xcode Cloud".
Device discovery and the gates are described in `docs/DEVICE_TESTING.md`.

AI simulation runs at two depths: a few hundred deterministic matches in fast
CI, thousands or tens of thousands nightly or before release (§112).

Screenshots are **not** regenerated on every commit. The full three-language
matrix runs for relevant UI or localisation changes and for release candidates;
ordinary CI runs only a screenshot smoke test (§109, §110).

---

## Prerequisites and open questions

| Item | Status |
|---|---|
| Xcode project with a shared scheme | does not exist (M0.2) |
| Ruby toolchain for Bundler-based fastlane | **undecided** — system Ruby is 2.6.10, too old; Homebrew `ruby@4.0` and `mise` are available |
| Xcode Cloud authorisation | OPEN (MAN-04) |
| App Store Connect app record | OPEN (MAN-02) |

§119 asks for a real Xcode Cloud run no later than after M1. That is currently
impossible for the two reasons above; it is recorded in `ROADMAP.md` rather than
glossed over.

---

## Local environment verified for this project

| Tool | Version |
|---|---|
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 |
| iOS SDK | 27.0 |
| Simulator runtimes | iOS 26.3, 26.5, 27.0 |
| xcodegen | 2.45.4 |
| swiftlint | 0.63.2 |
| swiftformat | 0.61.1 |
| xcbeautify | 3.2.1 |
| fastlane | 2.234.0 (Homebrew) |
| Ruby | 2.6.10 (system) |
