# Keezly — Game Center

**Implementation status: see the table at the end of this file.** The online model, the turn envelope and the transport boundary exist and are tested against a mock; the GameKit adapter is written but has never run against Game Center.
**Configuration status: CONFIGURED and ASC VERIFIED.** Game Center is enabled on
the App ID, the entitlement is in the shipped binary, and all ten achievements
exist at Apple in DE/NL/EN with artwork COMPLETE — each read back out of App
Store Connect (`APP_STORE.md`). No leaderboards, ever (DEC-025). What has never
happened is a real match between two accounts.

The three states are kept distinct throughout this project (§117, §138):

| State | Meaning |
|---|---|
| PREPARED | Files and code exist in the repository |
| CONFIGURED | The corresponding setting exists in App Store Connect / Xcode |
| VERIFIED | It has actually worked in a real run |

Nothing here is beyond "designed" yet.

Tracked as M6 in `ROADMAP.md`.

---

## Architecture decision

Online matches use **GameKit turn-based multiplayer**, not real-time `GKMatch`.
Reasoning and rejected alternatives: `DECISIONS.md` → DEC-006.

GameKit types must never appear in `KeezlyCore`, and never in view code either.
They are confined to one adapter behind a protocol, so tests can substitute a
double (§66).

```
Views  →  MatchSession  →  GameCenterServicing (protocol)
                                ├── LiveGameCenterService   (GameKit)
                                └── FakeGameCenterService    (tests)
```

---

## Scope for 1.0.0

- Authenticate `GKLocalPlayer` at launch; handle every failure gracefully.
  **The app stays fully usable for local and AI matches without Game Center.**
- Access point in the main menu and the profile area only — never floating over
  an active board (§60).
- Start a match, invite friends, automatch, 2–6 online participants.
- Load matches in progress, "your turn", opponent's turn, rematch, resign.
- Resume after the app is killed and relaunched.
- Several parallel online matches.

Matchmaking must only pair players with compatible settings: seat count, team
mode vs free-for-all, and rule set. A match's rule set never changes mid-match.

---

## Match state envelope (design)

```
OnlineMatchEnvelope
  schemaVersion       rejects a newer schema with a typed error
  appVersion
  rules               the frozen RuleSet
  seatConfiguration
  publicGameState     the serialised GameState
  turnRevision        monotonic; the basis for idempotency
  currentSeat
  randomizationState  the SeededGenerator state
  stateChecksum
  moveLog             compact, bounded
  participantMapping  GKPlayer ↔ Seat
```

Before every upload: `encodedData.count <= match.matchDataMaximumSize`. If the
full history would not fit, the envelope carries the current state plus a
compact move log, and long-term history is kept locally instead.

### What already exists

M2.9 is **done**. `GameStateEnvelope` in `KeezlyCore` already provides the
`schemaVersion` / `engineVersion` / `rulesVersion` / `stateChecksum` /
`publicGameState` part of the design above, refuses a newer schema and a
checksum mismatch with typed errors, and enforces a byte limit:

```swift
let data = try GameStateEnvelope.encode(state, maximumBytes: match.matchDataMaximumSize)
```

Measured payload size: a played-out **six-player** state encodes to **4527
bytes** — roughly 7 % of Game Center's 64 KiB turn-based budget. There is ample
headroom for `turnRevision`, `participantMapping` and a compact move log, so the
"fall back to state + move log" contingency is unlikely to be needed.

Still outstanding for M6.4: `turnRevision`, `participantMapping`, `moveLog`
(which needs M2.10) and the GameKit adapter itself.

---

## Idempotency (§28, §63)

Duplicated and out-of-order callbacks are expected, not exceptional. Every
submitted turn carries a unique move id, the previous revision and the resulting
revision. A callback whose `previousRevision` does not match the local state is
stale and is discarded, not applied. A state is never silently overwritten.

---

## Error cases to test (M6.7)

No network · not signed in · Game Center disabled · a player leaves · invitation
declined · match no longer available · app terminated mid-turn · app
backgrounded during upload · the same callback twice · local and remote state in
conflict · an older build opening a newer match state.

---

## Resignation policy

Team play: resigning forfeits the match for the whole team.
Free-for-all: the player is removed, their pawns leave the board, the others
play on, and the last remaining player wins.

This is already implemented and tested in the engine
(`GameFlowTests.resigningForfeitsTheTeam`,
`.resigningInFreeForAllLeavesOthersPlaying`).

---

## Achievements and leaderboards

Planned for M9, defined in `docs/GAME_CENTER_ACHIEVEMENTS.md` and
`docs/GAME_CENTER_LEADERBOARDS.md`. Neither file exists yet; neither has any
App Store Connect identifiers, because no app record exists.

---

## Apple Games / Game Activities

**Not evaluated yet.** Before implementing anything here, check which GameKit
APIs for Game Activities, multiplayer activities and party codes are actually
available and documented in the installed SDK. No imaginary API will be
implemented; if party codes do not fit the turn-based flow, the reason will be
recorded here rather than left unexplained (§33).

---

## Fairness: what is and is not protected (DEC-025)

**Every participant's device can reconstruct every hand and the remaining deck.**
Demonstrated by `OnlineHiddenInformationTests`, from the payload alone, using
nothing but the app's own loading path.

The cause is structural, not an oversight. Game Center gives every participant
the same `matchData`; that data carries the seed and the accepted moves,
because that is what makes the match reproducible and what lets a receiver
revalidate every remote move against the real engine. Reproducing the match
reproduces the deal.

Three different claims, which must never be run together:

| | Claim | Status |
|---|---|---|
| **A** | Keezly does not leak hidden information through its interface or its own agents | **Holds** — tested |
| **B** | A modified client cannot learn hidden information | **Does not hold** |
| **C** | Cheating is prevented — by a server, or by a correct multi-party protocol | **Not attempted** — either route would do it; neither is built |

Online play in 1.0.0 is friendly play. Nothing in the app, the store listing or
the documentation may claim otherwise, and online results are not a sound basis
for a competitive leaderboard (a constraint on M9).

The options evaluated — per-player encrypted hands, commit-and-reveal shuffles,
a server of our own, and GameKit's exchanges — are set out in DEC-025 with the
reason each was not taken.

---

## Status, as of M6

Kept apart on purpose, because they are different claims (§167):

| Part | Status |
|---|---|
| Turn envelope, revisions, idempotency, validation | **MOCK VERIFIED** — 29 tests against `InMemoryTransport` |
| Participant mapping, teams at 4 and 6 seats | **MOCK VERIFIED** |
| Two-client exchange across many turns | **MOCK VERIFIED** — 12 tests, clients sharing nothing but bytes |
| Several matches at once | **MOCK VERIFIED** |
| Quitting, finishing, refusing turns after the end | **MOCK VERIFIED** |
| Payload size against the 64 KiB limit | **MOCK VERIFIED** — measured, 4,173 bytes for 400 moves |
| Authentication state machine | **TESTED** — as a pure function, without GameKit |
| `GameCenterTransport` (the GameKit adapter) | **IMPLEMENTED, NOT VERIFIED** — never run against Game Center |
| Online play reachable from the menu | **IMPLEMENTED** — `OnlineMenuView` → `OnlineMatchRun` → `OnlineGameScreen`, shipping in 1.0.0 (42) |
| Seat/teams configuration for an online table | **VERIFIED** — one rule, `TableConfiguration.allowsTeams`; `OnlineConfigurationTests` builds every offerable pair. An odd seat count used to crash the app here (ISS-021) |
| Achievements in an online match | **NOT IMPLEMENTED** — absent by omission, not by rule; `GAME_CENTER_ACHIEVEMENTS_ONLINE.md` |
| A real match between two Apple Accounts | **OUTSTANDING** — MAN-11, MAN-12: needs two accounts and two devices. `GAME_CENTER_E2E_CHECKLIST.md` |
| Hidden information against a modified client | **NOT PROTECTED** — by design, see DEC-025 |

## How a turn travels

```
     device A                    Game Center                  device B
        │                             │                           │
  load(matchID) ────────────────────► │                           │
        │ ◄──────────────── compressed envelope                   │
        │                                                          │
  validate: version, checksum, replay every action,               │
            revision rises and lands where claimed,               │
            board checksum matches                                │
        │                                                          │
  OnlineMove(moveID, expectedRevision, action)                    │
        │                                                          │
  apply → accepted / duplicate / stale / out of order / rejected  │
        │                                                          │
  only if accepted:                                               │
  send(envelope, next: participant for the seat now on turn) ───► │
                                      │ ──────────────────────────►│
                                      │                    validate again,
                                      │                    from scratch
```

Nothing is held between turns. Every operation loads the match, checks it,
acts, and sends it on — which is what a turn-based game is: the app may be
closed between any two turns (§27).

## What the adapter still has to be right about

These are the parts no test covers, listed so they are checked first when a
real match becomes possible:

- Finding a `GKTurnBasedMatch` by the Keezly match id, which lives inside the
  payload rather than in Game Center's own identifier.
- Setting every participant's outcome when a match ends, or Game Center leaves
  it hanging for them.
- The turn timeout, currently a week.
- Mapping `gamePlayerID` to the identifiers in `ParticipantMapping` at the
  moment a match is created.
