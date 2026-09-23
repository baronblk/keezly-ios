# Keezly 1.0.0 — release checklist

Status vocabulary, kept strictly apart:

| | |
|---|---|
| **VERIFIED** | Done, and the result was read back from the thing that decides it |
| **DONE** | Done locally, not yet confirmed by Apple or by hardware |
| **HARDWARE PENDING** | Waiting on a physical device or a human ear |
| **OWNER ACTION** | A declaration or an account setting only the owner may make |
| **BLOCKED** | Cannot proceed, with the reason named |

Nothing here says "probably fine". Last updated **2026-09-23**.

---

## Can this be submitted tomorrow?

**Not yet — and the list is shorter than it was this morning:**

1. Game Center online has never run against real Game Center (tonight).
2. ~~Distribution signing~~ — **verified**, build 37.
3. No TestFlight build: Xcode Cloud cannot authenticate to upload. **Owner action** — agreements.
4. Four owner declarations are outstanding.
5. The screenshots are uploaded but no person has looked at them.

Items 1 and 5 need a human being, not more automation. Item 4 is the owner's by
definition. Items 2 and 3 are the same run and are in flight.

None of these is unknown territory. All are scheduled.

---

## Engine and app

| | Status | Evidence |
|---|---|---|
| Core engine suite | **VERIFIED** | 180 tests, 17 suites, including the AI soak and the payload-size test |
| App unit suite | **VERIFIED** | 232 tests, 29 suites |
| UI suite, iPhone + iPad | **VERIFIED** | 15 tests, 0 failures, from the lane's own JUnit |
| All UI classes together | **VERIFIED** | 34 tests, exit 0, capture suite included |
| SwiftLint `--strict`, SwiftFormat | **VERIFIED** | Clean |
| Compiler warnings | **VERIFIED** | None left but Xcode's own AppIntents notice |
| ISS-020 | **VERIFIED FIXED** | Was an iPhone tap-precedence bug, pinned by `BoardTapPrecedenceTests` |

## Game Center

| | Status | Evidence |
|---|---|---|
| Achievements exist at Apple | **VERIFIED** | Ten, read back, DE/NL/EN, artwork COMPLETE |
| The app reports achievements | **VERIFIED** | `AchievementReportingTests`, 7 tests |
| Online play reachable in the app | **DONE** | Implemented today; menu → online → match |
| Online rules (revision, duplicate, stale, corrupt) | **VERIFIED** | Core suite, `InMemoryTransport` |
| `.remote` seat role | **VERIFIED** | `OnlineSessionTests`, 9 tests |
| **Online against real Game Center** | **HARDWARE PENDING** | `GAME_CENTER_E2E_CHECKLIST.md`, two accounts, two devices |
| Entitlement in the built binary | **VERIFIED** | `com.apple.developer.game-center` in the cloud-built app |

## Xcode Cloud

| | Status | Evidence |
|---|---|---|
| Shared scheme from a clean clone | **VERIFIED** | Cloned `origin/main`, `xcodebuild -list` |
| Cloud BUILD | **VERIFIED** | Builds 4, 5, 11, 15 |
| Cloud ANALYZE | **VERIFIED** | Build 32, 0 errors **and 0 warnings** |
| Cloud TEST | **VERIFIED** | Build 32, 0 errors. Took four failures to get there, each a real defect |
| Cloud ARCHIVE | **VERIFIED** | Build 37 — .ipa downloaded and inspected |
| Distribution signing | **VERIFIED** | `Apple Distribution: RENÉ SUESS (KZFCCDV6A8)`, flags 0x0, real provisioning profile |
| TestFlight upload | **BLOCKED** | Xcode Cloud cannot authenticate with App Store Connect. 0 builds at Apple |
| Distribution signing | **NOT PROVEN** | Cloud build is Debug and ad-hoc. Only Archive exercises real signing |
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
| Screenshots | **UPLOADED** | 60 images at Apple; count, order and COMPLETE read back per set. **Not APP STORE VERIFIED** — that needs the owner's sign-off on SCREENSHOT_REVIEW.html |
| App Privacy declaration | **OWNER ACTION** | `APP_PRIVACY_OWNER_CHECKLIST.md` |
| Age rating | **OWNER ACTION** | One field wrong: Contests → None |
| Content rights | **OWNER ACTION** | `CONTENT_RIGHTS_OWNER_CHECKLIST.md` |
| DSA trader status | **OWNER ACTION** | Account level, not readable by API |
| Paid Apps agreement, tax, banking | **OWNER ACTION** | Not verifiable from here |
| Release mode = manual | **NOT SET** | To be set before submission |

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
| TestFlight smoke test | **BLOCKED** until a build exists |

---

## Deliberately not done

- **No Submit for Review.** Not today, and not tomorrow without explicit approval.
- **No external TestFlight beta review.** Archive distributes internally only.
- **No owner declaration made in the owner's name.**
- **No leaderboards** (DEC-025), and no claim of anti-cheat or server-authoritative play anywhere.
