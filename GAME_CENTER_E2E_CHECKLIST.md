# Game Center online — end-to-end test, two accounts, two devices

**Status before this runs: GAME CENTER ONLINE = NOT VERIFIED.**

Everything below is implemented and covered by tests that use
`InMemoryTransport` — two genuine clients reaching each other through bytes.
**Nothing has ever run against real Game Center.** `GameCenterTransport` is the
one file no test touches, because testing it needs two Apple Accounts on two
devices. That is what this session is for.

A single FAIL here is a release blocker, not a note.

---

## Before starting

| | |
|---|---|
| Device A | Physical iPhone, Keezly from TestFlight, **deleted and reinstalled** |
| Device B | Physical iPad, Keezly from TestFlight, **deleted and reinstalled** |
| Account A | Apple Account signed in to Game Center on A |
| Account B | **A different** Apple Account signed in to Game Center on B |
| Network | Both online. Have a way to turn Wi-Fi off on one device |

A clean install on both matters: an upgrade over a development build can carry
state that hides a first-run fault.

Check first, on each device: **Settings → Game Center → signed in**, and the
two accounts are genuinely different people.

---

## The twenty steps

Record PASS or FAIL for each. "Looked fine" is not a result.

| # | Step | Expect | A | B |
|---|---|---|---|---|
| 1 | A: open Keezly, main menu | "Play online" is visible | ☐ | — |
| 2 | A: tap "Play online" | The online screen; signed in, not a sign-in prompt | ☐ | — |
| 3 | B: same | Signed in as the *other* account | — | ☐ |
| 4 | A: choose seats, "New online match" | Either a match starts, or "Game Center is still looking for players" — **not** a hang and **not** a raw error | ☐ | — |
| 5 | B: open the online screen | The match appears in the list | — | ☐ |
| 6 | Both: check the table | Same number of seats on both; each device shows the other's name | ☐ | ☐ |
| 7 | Whoever is on turn: play a card | The move is accepted; the board updates | ☐ | ☐ |
| 8 | The other device: open the match | The move is there; it is now their turn | ☐ | ☐ |
| 9 | That device: play | Accepted | ☐ | ☐ |
| 10 | A: **force-quit Keezly entirely** (swipe away) | — | ☐ | — |
| 11 | B: play another turn while A is closed | Accepted | — | ☐ |
| 12 | A: relaunch from the home screen | Opens on the menu, no crash, no lost state | ☐ | — |
| 13 | A: open the match again | Shows B's turn, at the current position — not the old one | ☐ | — |
| 14 | Play several more turns, alternating | Each arrives; no duplicate pieces, no rewound board | ☐ | ☐ |
| 15 | Play the match to its end | Both devices show it finished | ☐ | ☐ |
| 16 | Check the winner | The banner on each device is right *for that device* — the winner sees "You won" and the loser does not | ☐ | ☐ |
| 17 | Check achievements | Game Center shows what the match earned. **Expect nothing from an online match** — Keezly reports achievements only for a table with one person at it, by design | ☐ | ☐ |
| 18 | B: turn Wi-Fi off, try to play a turn | A plain sentence about the connection. **No raw GKError, no code number, no hang, nothing blocking** | — | ☐ |
| 19 | B: turn Wi-Fi back on, retry | The turn goes through | — | ☐ |
| 20 | Both: reopen the match | Both devices agree on the position | ☐ | ☐ |

---

## Failure states worth provoking

These are the ones the code claims to handle. Each is covered by a unit test
against `InMemoryTransport`; none has been seen against Apple's service.

| What to do | Expect |
|---|---|
| Tap a card twice quickly on your turn | One move, not two |
| Play on A while B has the match open on screen | B catches up on refresh, and never applies the move twice |
| Force-quit **immediately after** tapping a move | Either the move went or it did not; the match must not be left half-played on reopening |
| Open the same match on both devices at once and both try to move | The one not on turn is told so, plainly |
| Sign out of Game Center in Settings, return to Keezly | The online screen says you are signed out and offers to sign in. No crash |
| Decline the Game Center sign-in | The rest of the app is unaffected |

---

## What a FAIL means

| Failing step | Meaning |
|---|---|
| 1–3 | Authentication or entitlement. Blocker |
| 4–6 | Matchmaking or seat mapping. Blocker — a wrong seat map means two devices playing different boards |
| 7–9 | The transport's send/load path. Blocker |
| 10–13 | Resume. Blocker — this is the whole point of a turn-based game |
| 14–16 | Revision handling or the outcome. Blocker |
| 17 | Expected to show nothing. If achievements *do* appear from an online match, the reporting rule is wrong |
| 18–19 | Error handling. Blocker if it shows a raw error, hangs, or loses a turn |
| 20 | Consistency. Blocker |

---

## Result

```
GAME CENTER ONLINE E2E:  ☐ PASS   ☐ FAIL
Date:
Devices:
Accounts (which two, not the addresses):
Notes:
```

Until this is signed off, `CURRENT_STATE.md` says **NOT VERIFIED**, and no
claim to the contrary belongs in any document, on the website, or in the store
listing.
