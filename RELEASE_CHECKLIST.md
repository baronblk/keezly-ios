# Keezly 1.0.0 — release checklist

Status vocabulary, kept strictly apart:

| | |
|---|---|
| **VERIFIED** | Done, and the result was read back from the thing that decides it |
| **DONE** | Done locally, not yet confirmed by Apple or by hardware |
| **HARDWARE PENDING** | Waiting on a physical device or a human ear |
| **OWNER ACTION** | A declaration or an account setting only the owner may make |
| **BLOCKED** | Cannot proceed, with the reason named |

Nothing here says "probably fine". Last updated **2026-09-23**, for build 42.

---

## Can this be submitted?

**Not yet.** What is outstanding now needs a person, not another commit:

1. **Nobody has played 1.0.0 (42) on hardware.** Build 41 was rejected by
   device QA; the crash it found is fixed, and the fix has not been played.
2. **Game Center online has never run against real Game Center.** Two devices,
   two accounts. `GAME_CENTER_E2E_CHECKLIST.md`.
3. **ISS-022 is open and unreproduced** — a reported backward move that the
   core is shown not to produce. It needs the concrete observation.
4. **Four owner declarations** are outstanding.
5. **The screenshots are uploaded but no person has looked at them.**
6. **One owner decision** — achievements in online matches, A or B.

The build itself is no longer in the way: 1.0.0 (42) is signed, validated by
Apple, processed and attached to version 1.0.0.

---

## Engine and app

| | Status | Evidence |
|---|---|---|
| Core engine suite | **VERIFIED** | 187 tests, 18 suites, including the AI soak and the payload-size test |
| App unit suite | **VERIFIED** | 239 tests, 31 suites |
| UI suite, iPhone + iPad | **VERIFIED** | 15 tests, 0 failures, from the lane's own JUnit |
| All UI classes together | **VERIFIED** | 34 tests, exit 0, capture suite included |
| SwiftLint `--strict`, SwiftFormat | **VERIFIED** | Clean |
| Compiler warnings | **VERIFIED** | None left but Xcode's own AppIntents notice |
| ISS-020 | **VERIFIED FIXED** | Was an iPhone tap-precedence bug, pinned by `BoardTapPrecedenceTests` |
| ISS-021 — online crash | **VERIFIED FIXED** | `OnlineConfigurationTests`, 5 tests, every offerable seat/teams pair |
| ISS-022 — reported backward move | **OPEN, UNREPRODUCED** | `MoveDirectionTests`, 7 tests: the Four is the only backward card, measured as progress, 2–6 seats. The UI holds no movement logic |
| Movement rules single-sourced | **VERIFIED** | `MoveGenerator` decides legality (DEC-004); the UI filters `observation.legalMoves` and previews through the core |

## Game Center

| | Status | Evidence |
|---|---|---|
| Achievements exist at Apple | **VERIFIED** | Ten, read back, DE/NL/EN, artwork COMPLETE |
| The app reports achievements | **VERIFIED** | `AchievementReportingTests`, 7 tests |
| Online play reachable in the app | **DONE** | Menu → online → match |
| Online seat/teams configuration | **VERIFIED** | One rule, `TableConfiguration.allowsTeams`; the menu no longer carries its own |
| Achievements in an online match | **NOT IMPLEMENTED** | Absent by omission, not by rule. Owner decision A/B: `GAME_CENTER_ACHIEVEMENTS_ONLINE.md` |
| Online rules (revision, duplicate, stale, corrupt) | **VERIFIED** | Core suite, `InMemoryTransport` |
| `.remote` seat role | **VERIFIED** | `OnlineSessionTests`, 9 tests |
| **Online against real Game Center** | **HARDWARE PENDING** | `GAME_CENTER_E2E_CHECKLIST.md`, two accounts, two devices |
| Entitlement in the built binary | **VERIFIED** | `com.apple.developer.game-center` in the shipped 1.0.0 (42) binary |

## Xcode Cloud

| | Status | Evidence |
|---|---|---|
| Shared scheme from a clean clone | **VERIFIED** | Cloned `origin/main`, `xcodebuild -list` |
| Cloud BUILD | **VERIFIED** | Builds 4, 5, 11, 15 |
| Cloud ANALYZE | **VERIFIED** | Build 32, 0 errors **and 0 warnings** |
| Cloud TEST | **VERIFIED** | Build 32, 0 errors. Took four failures to get there, each a real defect |
| Cloud ARCHIVE | **PRODUCES AN INVALID ARTEFACT** | The .ipa is signed, but `codesign --strict` and Apple's own validator both reject it: 90035. Cause is Apple's cloud-managed certificate writing the CN into the Designated Requirement as NFD while the certificate carries NFC |
| Cloud distribution signing | **FAILED** | An earlier "VERIFIED" here was wrong — only the authority line and the entitlements had been checked, never a strict verification and never Apple's validator |
| Cloud TestFlight upload | **BLOCKED** | Session proxy provider. Not attempted again |
| **Local distribution build** | **VERIFIED** | 1.0.0 (42): `codesign --verify --deep --strict` satisfied, certificate CN and requirement CN both NFC, `altool --validate-app` → VERIFY SUCCEEDED, upload → `processingState VALID`, attached to version 1.0.0 |
| Workflows CI / Main / Release | **VERIFIED** | Created and read back |
| Release toolchain pinned | **VERIFIED** | Xcode 27 (27A266a) |

## App Store Connect

| | Status | Evidence |
|---|---|---|
| App record, version 1.0.0 | **VERIFIED** | `6814932630`, `PREPARE_FOR_SUBMISSION` |
| Metadata DE/NL/EN, both levels | **VERIFIED** | Read back |
| Price €2.99, base DEU | **VERIFIED** | Read back |
| Categories | **VERIFIED** | Read back |
| Review information and notes | **VERIFIED** | Read back, 1819 characters |
| Export compliance | **VERIFIED** | No crypto, no own networking; only GameKit |
| Privacy manifest | **VERIFIED** | One required-reason API, re-checked after the online work |
| Screenshots | **ASC UPLOADED** | **45** images at Apple (7 per iPhone set, 8 per iPad set, 3 locales); count, order and COMPLETE read back per set. **Not HUMAN REVIEWED** — that needs the owner's sign-off in `SCREENSHOT_SIGNOFF.md` |
| Screenshots still match build 42 | **VERIFIED, NOT REGENERATED** | The only files changed between 41 and 42 are `Online/OnlineMenuView.swift` and `Online/OnlinePlay.swift`. No uploaded screenshot shows either screen — the online captures were excluded before upload and stay excluded (`scripts/screenshot-select.py`), because in a simulator that screen can only show a Game Center authentication failure. A happy-path online shot needs a real account on real hardware |
| App Privacy declaration | **OWNER ACTION** | `APP_PRIVACY_OWNER_CHECKLIST.md` |
| Age rating | **OWNER ACTION** | Reads back as `FOUR_PLUS`, which is right; one answer behind it is wrong — Contests → None. `AGE_RATING_OWNER_CHECKLIST.md` |
| Content rights | **OWNER ACTION** | `CONTENT_RIGHTS_OWNER_CHECKLIST.md` |
| DSA trader status | **OWNER ACTION** | Account level, not readable by API |
| Paid Apps agreement, tax, banking | **OWNER ACTION** | Not verifiable from here |
| Build attached to 1.0.0 | **VERIFIED** | Build 42, read back from ASC |
| TestFlight availability | **VERIFIED** | `internalBuildState IN_BETA_TESTING`, `externalBuildState READY_FOR_BETA_SUBMISSION` — **not** Internal Only |
| Release mode = manual | **VERIFIED** | `releaseType = MANUAL`, read back |
| Ten achievements at Apple | **VERIFIED** | Read back by vendor identifier, none archived. `achievementReleases` is 0 and stays 0 until a version goes live — that is not a fault |
| Leaderboards | **VERIFIED ABSENT** | 0, and DEC-025 says it stays 0 |

## Website

| | Status | Evidence |
|---|---|---|
| Built, 15 pages, three languages | **VERIFIED** | `website-check.py` |
| Describes the real 1.0 scope | **VERIFIED** | Online play restored; offline overclaim corrected |
| Legal content | **VERIFIED** | Owner-supplied and confirmed |
| Live at `gcng.de/KEEZLY/` | **OWNER ACTION** | Not uploaded. Not LIVE VERIFIED |

## Hardware, tonight

| | Status |
|---|---|
| Clean install, iPhone | **HARDWARE PENDING** |
| Clean install, iPad | **HARDWARE PENDING** |
| Game Center E2E, two accounts | **HARDWARE PENDING** |
| Audio on hardware | **HARDWARE PENDING** — `AUDIO_REVIEW.md` |
| App icon seen on a real home screen | **HARDWARE PENDING** |
| ISS-019 password prompt | **HARDWARE PENDING** — diagnose interactively, store nothing |
| TestFlight smoke test | **HARDWARE PENDING** — 1.0.0 (42) is available to install |
| Online match at every seat count 2–6 | **HARDWARE PENDING** — the ISS-021 regression, played rather than tested |
| ISS-022 — record card, seat, table size, where the piece went | **HARDWARE PENDING** |

---

## Deliberately not done

- **No Submit for Review.** Not today, and not tomorrow without explicit approval.
- **No external TestFlight beta review started.** The build is *capable* of one
  (`READY_FOR_BETA_SUBMISSION`); starting one is the owner's decision.
- **No owner declaration made in the owner's name.**
- **No leaderboards** (DEC-025), and no claim of anti-cheat or server-authoritative play anywhere.
