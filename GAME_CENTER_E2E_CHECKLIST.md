# Game Center online — end-to-end, two devices, two accounts

**Status until this has been run: GAME CENTER E2E = NOT VERIFIED.**

It becomes VERIFIED on one condition and no other: **a real match was played to
completion between the two accounts, and every step below says PASS.** Not
"mostly worked", not "the hard parts worked". A single FAIL is a release
blocker; a step left NOT TESTED leaves the whole gate NOT VERIFIED.

Everything here is implemented and covered by tests against
`InMemoryTransport` — two genuine clients reaching each other through bytes.
**None of it has run against Apple's service.** `GameCenterTransport` is the one
file no test touches, because testing it needs two Apple Accounts on two
devices. That is what this document is for.

---

## Setup

| | |
|---|---|
| Build | **TestFlight, the current candidate.** Not a development build |
| Device A | **iPhone** — Keezly deleted and reinstalled from TestFlight |
| Device B | **iPad** — Keezly deleted and reinstalled from TestFlight |
| Account A | An Apple Account signed in to Game Center on the iPhone |
| Account B | **A different** Apple Account signed in to Game Center on the iPad |
| Network | Both online. Have a way to turn Wi-Fi off on one device |

A clean install on both matters: an upgrade over a development build can carry
state that hides a first-run fault.

Check before starting, on each device: **Settings → Game Center → signed in**,
and the two accounts are genuinely two different people.

```
Build (version and number):
Date:
iPhone model / iOS:                      Account A (a name, not an address):
iPad model / iOS:                        Account B:
```

---

## Two things this build does not have

Written down here so a missing button is not recorded as a FAIL.

- **There is no "invite a friend by name".** Keezly matchmakes with
  `GKTurnBasedMatch.find`, so Game Center picks the opponent. If Apple's own
  matchmaking sheet offers to invite somebody, that is Apple's sheet, and the
  invitation steps below are tested through it.
- **There is no "Rematch" button.** A second match is started the same way the
  first one was. Step 20 tests that, not a rematch feature.

---

## Step 0 — the crash from build 41 (ISS-021)

Before anything else. It happened on the way *into* a match, before Game Center
was ever called, so it costs a minute and it gates everything after it.

| | Expect | A | B |
|---|---|---|---|
| 0.1 Open online, **3** seats, start | No crash | ☐ | ☐ |
| 0.2 Open online, **5** seats, start | No crash | ☐ | ☐ |
| 0.3 **4** seats → change to **3** → start | No crash | ☐ | ☐ |
| 0.4 **6** seats → change to **5** → start | No crash | ☐ | ☐ |
| 0.5 Teams offered at 4 and 6 only | Never at 2, 3 or 5 | ☐ | ☐ |

**Any crash here is ISS-021 returning and stops the run.**

---

## The run

Mark each step **PASS**, **FAIL** or **NOT TESTED**. "Looked fine" is not a
result, and an empty box is NOT TESTED.

### Login

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 1 | Open Keezly | Main menu, "Play online" visible | | |
| 2 | Tap "Play online" | The online screen, already signed in — not a sign-in prompt | | |
| 3 | Check which account | Each device shows **its own** account, and they differ | | |

### Match erstellen · Einladung · Annehmen

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 4 | A: choose the seat count, "New online match" | A match starts, **or** a plain sentence that Game Center is still looking. Not a hang, not a raw error | | — |
| 5 | If Apple's matchmaking sheet appears | It is Apple's, it is readable, and cancelling it returns to Keezly cleanly | | — |
| 6 | B: open the online screen | The match is in the list | — | |
| 7 | B: open it | The board appears; B is a participant | — | |
| 8 | Both: compare the table | Same seat count on both; each device shows the other's name; each shows **its own** seat as its own | | |

### Turn

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 9 | Whoever is on turn: play a card | Accepted; the board updates; the turn passes | | |
| 10 | The other device: open the match | The move is there, and it is now their turn | | |
| 11 | That device: play | Accepted | | |

### Gerätewechsel

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 12 | Alternate turns three times, watching the other screen each time | Every move arrives; no duplicated piece; no rewound board | | |
| 13 | While it is **not** your turn, try to move | The board is closed, politely — not a raw refusal and not a silent nothing | | |

### App Kill · Resume

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 14 | A: **force-quit Keezly** (swipe it away) | — | | — |
| 15 | B: play a turn while A is closed | Accepted | — | |
| 16 | A: relaunch from the home screen | Opens on the menu, no crash | | — |
| 17 | A: open the match again | The **current** position, including B's move — not the old one | | — |
| 18 | A: force-quit **immediately after** tapping a move, then reopen | Either the move went or it did not. Never half-played | | — |

### Mehrere Turns, and the cards that are hard

Play on until each of these has actually happened. If the deal does not offer
one, say NOT TESTED rather than guessing — an untested Seven is not a passed
Seven.

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 19 | **Seven split** across two pieces | Both legs travel forward; seven steps in total; the other device sees the same two pieces move | | |
| 20 | **Jack swap** with another player's piece | Exactly two pieces exchange places, and the same two on both devices | | |
| 21 | **Capture** — knock a piece back to its waiting area | The right piece goes home to wait, on both devices | | |
| 22 | **Home** — an exact count into the home lane | It enters; an overshoot is refused | | |
| 23 | **Four backwards** | It moves back four, and nothing else in the match ever moves backward (ISS-022) | | |

### Match Completion

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 24 | Play the match to its end | Both devices show it finished | | |
| 25 | Check the outcome | Right *for that device*: the winner sees they won, the loser does not | | |
| 26 | Reopen the finished match on both | Both agree on the final position | | |

### Achievement

**This is new in this build.** An online match now reports achievements for the
local player's own seat. It did not before, and the reason it did not — that a
shared device has no single owner — never applied to an online seat, which
belongs to exactly one Game Center account.

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 27 | Watch the end of the match | Game Center's own banner appears for what was earned | | |
| 28 | Game Center app → Keezly → Achievements, on each device | The achievements that match **what that account actually did** | | |
| 29 | **The winner's device only** shows "Won" | The loser must **not** have been given it | | |
| 30 | Close Keezly, reopen it, open the finished match again | **No second banner.** Nothing is awarded again | | |
| 31 | Force-quit, relaunch, open the finished match | Still no second award | | |
| 32 | Check the other account's achievements | Only what *that* account earned. Nothing of the opponent's | | |

Steps 30 and 31 are the ones worth being slow about. Duplicate awarding is the
failure mode this feature is most likely to have, and it is invisible unless
somebody deliberately reopens a finished match.

### Rematch / neue Partie

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 33 | Start a second match between the same two accounts | It starts, and is a **new** board — not the finished one | | |
| 34 | The finished match in the list | Still shown as finished, not resurrected | | |
| 35 | Play a turn in the new match | Accepted; the old match is unaffected | | |
| 36 | Finish the second match | Its achievements report too — the ledger must not have blocked a match it never saw | | |

---

## Failure states worth provoking

Each is covered by a unit test against `InMemoryTransport`; none has been seen
against Apple's service.

| What to do | Expect | Result |
|---|---|---|
| Tap a card twice quickly on your turn | One move, not two | |
| Both devices open the match at once, both try to move | The one not on turn is told so, plainly | |
| B: turn Wi-Fi off, try to play | A plain sentence about the connection. **No raw GKError, no code number, no hang** | |
| B: Wi-Fi back on, retry | The turn goes through | |
| Sign out of Game Center in Settings, return to Keezly | Says you are signed out and offers to sign in. No crash | |
| Decline the Game Center sign-in | The rest of the app is unaffected | |

---

## What a FAIL means

| Failing step | Meaning |
|---|---|
| 0.x | ISS-021 has returned. Blocker, and stop |
| 1–3 | Authentication or entitlement. Blocker |
| 4–8 | Matchmaking or seat mapping. Blocker — a wrong seat map means two devices playing different boards |
| 9–13 | The transport's send/load path. Blocker |
| 14–18 | Resume. Blocker — this is the whole point of a turn-based game |
| 19–23 | A rule behaving differently over the wire than it does locally. Blocker. A backward move that is not a Four belongs in the ISS-022 form |
| 24–26 | Revision handling or the outcome. Blocker |
| 27–29 | Achievements not reported, or reported for the wrong account. Blocker — reporting somebody else's win is worse than reporting nothing |
| 30–32 | **Duplicate awarding.** Blocker |
| 33–36 | A second match blocked or confused by the first. Blocker |
| Wi-Fi rows | Error handling. Blocker if it shows a raw error, hangs, or loses a turn |

---

## Result

Fill this in from the boxes above, not from an impression of how it went.

```
Steps PASS:            /36
Steps FAIL:
Steps NOT TESTED:

GAME CENTER E2E:   ☐ VERIFIED   ☐ FAILED   ☐ INCOMPLETE

VERIFIED requires: a real match played to completion between two accounts,
36 PASS, 0 FAIL, 0 NOT TESTED.

Anything that failed, and exactly what happened:
```
