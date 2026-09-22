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

## Game Center — LOCAL PREPARED

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

`scripts/asc_push_achievements.rb` validates everything — unique ids, points
within Apple's limits, all three locales present, every image on disk — and
then reports that **Apple's Game Center endpoints are not reachable through
this tooling**: `fastlane` 2.240 has no `GameCenterDetail` model, and the raw
paths answer *"The path provided does not match a defined resource type."*
Creating them is a web-form step.

---

## Screenshots — NOT YET UPLOADED

The existing 84-capture matrix predates the locale and status-bar fixes and
**must not be used**. A fresh matrix is required, then the ten strongest per
device and locale selected — Apple allows ten, the pipeline produces fourteen.

---

## Outstanding

| | Waiting on |
|---|---|
| Website URLs live | Owner upload to `gcng.de/KEEZLY/`, then HTTP check |
| App Privacy declaration | Owner, in the web form |
| Age rating questionnaire | Owner, in the web form |
| DSA trader status | Owner — a legal self-declaration |
| Pricing and availability | Owner decision, not documented anywhere yet |
| Game Center achievements | Web form; everything they need is prepared |
| Screenshots | Fresh matrix, then upload |
| TestFlight | A green build |
