# App Privacy — for the owner to confirm

**This is not filled in on the owner's behalf.** Every line below is a fact
about the code with the evidence beside it, and a *proposed* answer. The
declaration itself is made under the owner's name in App Store Connect and is
his to submit.

Audited against the shipping code on **2026-09-23**, after Game Center online
play was implemented. The earlier audit predates that and is superseded.

---

## The short answer, and the one thing that needs a decision

Proposed: **Data Not Collected** for every Apple category.

The one line that is genuinely arguable is the Game Center player identifier,
because online play puts it in the match payload. It is set out in full under
*Identifiers* below. Everything else is a plain no.

---

## What the app writes, reads and sends — all of it

| What | Where | Evidence |
|---|---|---|
| `keezly.sound`, `keezly.haptics` | `UserDefaults`, this device | `Feedback.swift` → `Preferences` |
| `keezly.hasPlayed` | `UserDefaults`, this device | `Welcome.swift` |
| Saved matches | Application Support, this device | `MatchStore.swift` |
| Online match payload | Game Center, to the other players in that match | `OnlineMatchEnvelope.swift` |
| Achievement completions | Game Center | `GameCenterAchievements.swift` |

Nothing else leaves the device. There is no server of ours, no analytics, no
crash reporter, no advertising and no third-party SDK — the only dependency is
`KeezlyCore`, which is in this repository.

Frameworks imported by the whole app: `AVFoundation`, `CoreGraphics`,
`Foundation`, `GameKit`, `KeezlyCore`, `Observation`, `SwiftUI`, `UIKit`.
No `URLSession`, no `Network`, no `CryptoKit`.

---

## Apple's questions, one at a time

| Apple's category | Proposed answer | Why, from the code |
|---|---|---|
| Contact Info | **No** | No name, email, address or phone is asked for or stored. There is no sign-up |
| Health & Fitness | **No** | No HealthKit, no sensors |
| Financial Info | **No** | No purchases in the app, no payment code. The app is paid once on the store |
| Location | **No** | No CoreLocation, no location permission in `Info.plist` |
| Sensitive Info | **No** | None collected |
| Contacts | **No** | No Contacts framework. Game Center friends are Apple's, inside Apple's own UI, and never read by Keezly |
| User Content | **No** | Nothing a player types is stored — there is nothing to type. No chat, no names, no photos |
| Browsing History | **No** | No web view, no browser |
| Search History | **No** | No search |
| **Identifiers** | **see below** | The Game Center player identifier is used for seat mapping |
| Purchases | **No** | No in-app purchases, no receipt handling |
| Usage Data | **No** | No analytics SDK, no event logging, no product interaction reporting |
| Diagnostics | **No** | No crash reporter, no performance data collected or sent |
| Other Data | **No** | — |

---

## Identifiers — the line that needs the owner's judgement

**The fact.** An online match maps seats to players by Game Center's
`gamePlayerID`. Those identifiers travel inside the match payload, which Game
Center delivers to the other players in that match.

```
OnlineMatchEnvelope → participants: ParticipantMapping → seatOrder: [String]
```

Also: the *display names* of the other players are shown in the match list.
They are read from `GKTurnBasedParticipant`, shown on screen, and never stored.

**Why "Data Not Collected" is still proposed:**

- `gamePlayerID` is Apple's identifier, scoped to this app and this player by
  Apple, and is **not** the IDFA, the identifier for vendors, or anything from
  the hardware.
- It is not collected *by us*: there is no server of ours, nothing is retained
  off-device, and the developer never receives it. It goes from Apple's
  framework, through Apple's service, to the other player's copy of the app.
- It is not used for tracking, not linked to any other identity, and not shared
  with a third party. There is no third party.

**Why it is nonetheless worth the owner's eye:** Apple's form asks about data
the app *collects*, and reasonable people read "put an identifier into a
payload and transmit it" differently. If the owner prefers the conservative
answer, the correct one is **User ID → App Functionality → not linked to
identity → not used for tracking**, which is truthful and costs nothing.

**Owner decision required: ☐ Data Not Collected  ☐ User ID, App Functionality**

---

## Tracking

**No.** `NSPrivacyTracking` is `false` in `PrivacyInfo.xcprivacy`, the tracking
domain list is empty, and there is no ATT prompt because there is nothing to
ask for. Nothing is shared with a data broker or an advertising network,
because nothing is shared at all.

---

## Privacy manifest — matches the code

`App/Keezly/PrivacyInfo.xcprivacy` declares exactly one required-reason API:

| API | Reason | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Two feedback switches and the newcomer flag, read and written only by this app |

File timestamps, disk space, system boot time and active keyboards are **not
used**, so none is declared. Re-checked after the online work: it added no
required-reason API.

---

## What the owner needs to do

1. Open App Store Connect → Keezly → App Privacy.
2. Answer the categories above. All are **No** except the Identifiers decision.
3. Confirm tracking is **No**.
4. Publish the declaration.

Nothing in this file is submitted automatically, and nothing here should be
taken as legal advice.
