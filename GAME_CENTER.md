# Keezly — Game Center

**Implementation status: NOT STARTED.** No GameKit code exists.
**Configuration status: NOT CONFIGURED.** Nothing has been set up in App Store
Connect. See `CURRENT_STATE.md` → Manual Actions (MAN-02, MAN-05, MAN-06).

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

This depends on M2.9 (versioned serialisation), which does not exist yet —
`GameState` is `Codable` today but carries no version field.

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
