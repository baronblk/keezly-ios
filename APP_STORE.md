# Keezly — App Store Connect

**Status: NOT SUBMITTED.** Nothing here has been sent for review and nothing is
scheduled for release. The stop line is the owner's: no *Submit for Review*, no
external TestFlight beta review, no automatic release.

| | |
|---|---|
| ASC App ID | `6814932630` |
| Bundle ID | `de.gcng.keezly` (Apple id `5AH4Z7666T`) |
| SKU | `KEEZLY-IOS-001` |
| Primary locale | `de-DE` |
| Version | `1.0.0`, state `PREPARE_FOR_SUBMISSION` |
| Platform | iOS — iPhone and iPad |
| Categories | `GAMES` / `GAMES_BOARD` / `GAMES_CARD` |
| Copyright | `© 2026 Rene Süß` |
| Price | **€2.99**, base territory Germany (proceeds €2.14) |

Everything below is separated into **LOCAL PREPARED**, **ASC UPLOADED** and
**ASC VERIFIED**. Verified means it was read back out of App Store Connect
afterwards, not that a request returned 200.

---

## What the record disagreed with, and what was done

Found by reading the record rather than assuming it matched the brief:

| | Expected | Found | Action |
|---|---|---|---|
| Version string | `1.0.0` | `1.0` | Changed to `1.0.0` — a mismatch with `MARKETING_VERSION` is refused at upload |
| App name | `Keezly: Keezenspel` | `KEEZLY: KEEZENSPEL` | Corrected |
| Primary locale | `nl-NL` preferred | `de-DE` | **Left as de-DE.** It cannot be changed after creation |

Apple refuses `whatsNew` on a version that has never shipped, which is correct —
there is nothing new about 1.0.0. The release notes in
`fastlane/metadata/*/release_notes.txt` are kept for the first update and for
the TestFlight note.

---

## Localizations — ASC VERIFIED

Both levels, all three locales. A locale present at only one level is half a
locale and App Store Connect does not say which half is missing.

| Locale | App Info | Version 1.0.0 | Description | Keywords | Promo |
|---|---|---|---|---|---|
| de-DE | name, subtitle, privacy URL | ✓ | 1960 chars | 96 | 113 |
| nl-NL | name, subtitle, privacy URL | ✓ | 1896 chars | 93 | 118 |
| en-US | name, subtitle, privacy URL | ✓ | 1778 chars | 95 | 109 |

Written per language rather than translated. Keywords are chosen per market;
two were over Apple's 100-character limit until `scripts/metadata-check.sh`
said so.

`scripts/metadata-check.sh` also fails on any claim the software cannot keep —
anti-cheat, server-authorised play, leaderboards, Game Center matchmaking
guarantees — in any of the three languages, because there is no server that
could make them true (DEC-025).

Push and verify with:

```bash
bundle exec ruby scripts/asc_push_metadata.rb
```

---

## Export compliance — VERIFIED

`ITSAppUsesNonExemptEncryption` is `false`, and that is audited rather than
asserted:

- No `CryptoKit`, no `CommonCrypto`, no `SecKey`, no AES or RSA anywhere in
  `App/` or `Packages/`.
- No `URLSession` and no `Network` framework. The only networking in the
  project is GameKit, which is Apple's own and uses the operating system's
  encryption — exempt.
- The key is present in the built `Info.plist`, so the question is answered
  once rather than at every upload.

---

## Privacy manifest — VERIFIED

`App/Keezly/PrivacyInfo.xcprivacy` ships in the bundle and declares exactly one
required-reason API:

| API | Reason | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Two feedback switches and the newcomer flag, read and written only by this app |

Audited against the code: file timestamps, disk space, system boot time and
active keyboards are **not used**, so none is declared. Tracking is false, the
tracking-domain list is empty and the collected-data list is empty, each because
it is.

---

## App Privacy — LOCAL PREPARED

The answer is **No data collected**, and the audit behind it:

| Category | Finding |
|---|---|
| Own collection | None. Three `UserDefaults` keys and saved matches, all on device |
| Identifiers | None. The match id is a `UUID` made at deal time — not the IDFA, not the identifier for vendors, nothing from the hardware |
| Analytics / diagnostics | None. No analytics SDK, no crash reporter |
| Advertising | None |
| Third-party SDKs | None. The only dependency is `KeezlyCore`, which is in this repository |
| Game Center | Apple's service under Apple's own policy. Keezly sends the state of the match in progress and nothing else |

The declaration itself is made in the App Store Connect web form under the
owner's name and is not something to automate.

---

## Pricing — ASC VERIFIED

**€2.99**, base territory `DEU`, set as a manual price on the app's price
schedule and read back from Apple. Apple derives every other territory from the
German price.

The owner gave the figure as "2,99". Read as euro — German decimal comma,
German-primary app, German seller — and confirmed against Apple's own price
point for `DEU`, which lists a customer price of 2.99 and proceeds of 2.14. If
a different currency was meant, the schedule is a single call to change.

---

## Game Center — ASC VERIFIED (metadata only)

Enabled on the App ID. The ten achievements are defined in code, which is the
source of truth because **achievement ids are permanent**:

`App/Keezly/Stats/Achievement.swift` → `de.gcng.keezly.achievement.<case>`

| Achievement | Points |
|---|---|
| finished | 5 |
| won | 10 |
| untouched | 20 |
| split | 10 |
| swapped | 5 |
| backwards | 5 |
| knockout | 5 |
| resilient | 15 |
| fullTable | 10 |
| partners | 15 |

100 points of Apple's 1000, weighted by difficulty rather than flat. Titles and
both descriptions exist in de-DE, nl-NL and en-US in the app's own string
catalogue. Artwork is generated from source by `Tools/achievementart.py` — ten
1024×1024 RGB images in the board's design language, no alpha.

**No leaderboards**, and none will be created: online results cannot be ranked
honestly while a modified client can read every hand (DEC-025).

All ten exist in App Store Connect, created through the REST API by
`scripts/asc_game_center.rb` and **read back afterwards** rather than inferred
from a 201:

| Vendor identifier | Points | Apple id | DE | NL | EN | Images |
|---|---|---|---|---|---|---|
| `…achievement.backwards` | 5 | `675c5e5c-decd-47c2-9fe2-2884d3652555` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.finished` | 5 | `d942c90a-9230-4387-8cd6-f1eb1dbe72ba` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.fullTable` | 10 | `d7aac7ed-ac7a-4b1b-9941-695d1b348e8e` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.knockout` | 5 | `22495c63-4cdd-47ea-8901-9f556ae5ae64` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.partners` | 15 | `0ceba930-67d6-4db4-9b39-0bc278164b94` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.resilient` | 15 | `51ade891-8654-448a-b140-75e907d6882b` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.split` | 10 | `e0297192-f15a-4288-8902-8bd8a2d041b6` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.swapped` | 5 | `8f0291a8-72f1-48fb-b239-fafd68ece398` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.untouched` | 20 | `ad267c89-cbf6-4861-924c-153807e5b635` | ✓ | ✓ | ✓ | COMPLETE |
| `…achievement.won` | 10 | `983e9ab0-cecc-4e37-a625-c2b5841921fe` | ✓ | ✓ | ✓ | COMPLETE |

Game Center detail: `0b989385-b0bf-42a1-acac-c962cdce951b`.

An earlier version of this document said these needed a web form. That was
wrong: only **v1** paths had been probed, and the v2 resources that Apple
documents were never tested. `POST /v2/gameCenterAchievements` works.

### The app did not report any of them

Found by reading the app rather than the record, on 2026-09-22. All ten existed
at Apple, `AchievementEvaluator.unlocked(in:for:)` was fully tested — and
**nothing in the app ever submitted a `GKAchievement`**. `GameKit` was imported
by exactly one file, `GameCenterTransport`, which nothing referenced;
`GameCenterAuthentication` was referenced by nothing at all. A player could have
earned every one of them and been told about none.

`AchievementReportingTests` now pins the rule, and the gap it was written for:
`AchievementTests` could never have caught this, because the evaluator was
right the whole time. What was missing was anything that called it.

Reported for a solo table. **Not** for pass & play: several people share the
device and one of them owns the Game Center account, so crediting the first seat
would attribute somebody else's win to the owner.

**Not for an online match either — and that one is an omission, not a rule.** An
online seat belongs to exactly one Game Center account, so the attribution
problem above does not arise there; nothing reports it because
`MatchSession.init(online:)` is handed no reporter at all. Whether 1.0.0 wires
this up is an owner decision with two clean answers, written out in
`GAME_CENTER_ACHIEVEMENTS_ONLINE.md`. Until it is taken, the store listing and
the TestFlight notes say online earns nothing, which is true.

**GAME CENTER E2E = NOT VERIFIED.** Metadata existing is not the same as a
signed-in account on a real device seeing a banner, and that has not happened
yet. The reporting path is covered by tests that use a spy, not by Apple.

---

## Online play in 1.0.0

`GameCenterTransport` implements turn-based play over `GKTurnBasedMatch`, and
1.0.0 reaches it: menu → online → match, with `OnlineMenuView`,
`OnlineMatchRun` and `OnlineGameScreen` in front of it. It ships.

This section previously said the opposite, and that was true when it was
written: the transport compiled into the binary and nothing in the interface
reached it, while the website promised online play on the home page, in the FAQ
and on all three privacy pages. The interface was built rather than the promise
withdrawn — online play is 1.0.0 scope by the owner's decision.

What is *not* claimed anywhere: friend invitations by name (matchmaking is
`GKTurnBasedMatch.find`), leaderboards (DEC-025, never), and any form of
anti-cheat or server-authoritative play. There is no server.

---

## Review Information — ASC VERIFIED

| | |
|---|---|
| Contact | Rene Süß · support@gcng.de · +4915155386821 |
| Demo account | Not required, and that is now stated rather than left blank |
| Notes | 1819 characters, read back from Apple after writing |

The notes tell a reviewer there is no sign-in, name every main-menu button
exactly as the app spells it, and explain that the pass & play cover is
deliberate rather than a loading screen — the one thing about Keezly a reviewer
could reasonably mistake for a bug.

Three screen names in the first draft were invented (`Play`, `Statistics`, "I
have the device"). The app says `Start game`, `Matches` and `I have it`. Checked
against `Localizable.xcstrings` and corrected before they reached Apple.

---

## Age rating — ANSWERED, NOT AUDITED BY THE OWNER

The declaration exists and reads as all-`NONE` except one line:

```
contests: INFREQUENT_OR_MILD
```

Everything else — violence, gambling, simulated gambling, profanity, horror,
drugs, weapons, sexual content, unrestricted web access, user-generated
content, messaging, advertising, loot boxes — is `NONE` or `false`, which
matches the app.

`contests` does not. Apple's question is about contests and sweepstakes run
**through the app**; a competitive board game is not one, and Keezly offers no
prize, entry or draw of any kind. It looks like it should be `NONE`.

**Not changed.** An age rating is a declaration in the owner's name, and this
one is his to make. It is one field in the web form, or one PATCH.

---

## Screenshots — ASC UPLOADED, NOT YET REVIEWED BY A PERSON

60 images: ten per device size, per locale. Read back from Apple rather than
inferred from a 201 — count, filename order and `assetDeliveryState COMPLETE`
confirmed for every one of the six sets.

| Locale | iPhone 6.9″ | iPad 13″ |
|---|---|---|
| de-DE | 10, order ok, COMPLETE | 10, order ok, COMPLETE |
| nl-NL | 10, order ok, COMPLETE | 10, order ok, COMPLETE |
| en-US | 10, order ok, COMPLETE | 10, order ok, COMPLETE |

Captured from a 132-image matrix — 22 scenes across two devices and three
locales — generated after every fix of the last two days, including the board
tap-precedence repair. Nothing older is in the release path; the superseded set
is archived under `artifacts/screenshots-superseded-*`.

**One orientation per series.** The iPhone set is portrait throughout and the
iPad set landscape throughout: a store sequence that flips halfway looks like a
mistake even when every image in it is right. That cost six new portrait
captures and one new landscape one, and it is the difference between a set of
images and a series.

The selection is a judgement and is written down as one — an ordered list with
a reason against every slot in `scripts/screenshot-select.py`, so any single
choice can be overruled without re-deriving the rest.

**Not APP STORE VERIFIED.** That needs a person to open
`SCREENSHOT_REVIEW.html` and answer the ten questions per image that no script
can: whether the language is right, whether the board is worth showing, whether
the feature shown genuinely exists in this build, whether it is good enough to
sell the app. Nothing in that sheet is pre-ticked.

---

## Xcode Cloud — CANNOT BE CREATED BY API

Not a guess and not a fastlane limitation. Apple's own refusals, read today:

```
GET  /v1/ciWorkflows   403  The resource 'ciWorkflows' does not allow
                            'GET_COLLECTION'. Allowed: CREATE, DELETE,
                            GET_INSTANCE, UPDATE
POST /v1/ciProducts    403  The resource 'ciProducts' does not allow 'CREATE'.
                            Allowed: DELETE, GET_COLLECTION, GET_INSTANCE
```

So a workflow *can* be created over the API — but only against a `ciProduct`,
and a `ciProduct` cannot be created over the API at all. The account currently
has:

| | |
|---|---|
| `ciProducts` | **0** |
| `scmRepositories` | **0** |
| `scmProviders` | 1 — GitHub Cloud, `github.com`, already authorised |
| Repositories under that provider | **0** |

The GitHub connection exists; no repository has been attached to it. Onboarding
the product is done once, from Xcode's *Product → Xcode Cloud → Create
Workflow*, and it grants Apple access to the repository — an authorisation in
the owner's name, which is his to give.

Once one `ciProduct` exists, the three workflows are `POST /v1/ciWorkflows` and
can be scripted from here. Available `ciMacOsVersions` and `ciXcodeVersions`
were read back and include *Latest Release* for both, which is what a workflow
should pin to.

---

## Outstanding

| | Waiting on |
|---|---|
| Website URLs live | Owner upload to `gcng.de/KEEZLY/`, then HTTP check |
| App Privacy declaration | Owner, in the web form |
| Content rights declaration | Owner — `contentRightsDeclaration` is still null, and it is a rights statement in his name |
| Age rating questionnaire | Owner, in the web form |
| DSA trader status | Owner — a legal self-declaration |
| Screenshots | Fresh matrix, then upload |
| TestFlight | A green build |
| Xcode Cloud | Owner — one onboarding in Xcode; the API cannot create a `ciProduct` |
