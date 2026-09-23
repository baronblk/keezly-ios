# Physical device tests — iPhone and iPad, tonight

Run on the **TestFlight build**, after deleting any existing Keezly. An upgrade
over a development build can carry state that hides a first-run fault, so the
clean install is not optional.

Two columns because the two devices are not the same product: the iPad is a
first-class platform here, not a stretched phone.

```
Build tested:            iPhone model / iOS:
Date:                    iPad model / iOS:
```

---

## Install and first launch

| | iPhone | iPad |
|---|---|---|
| Keezly fully deleted first | ☐ | ☐ |
| Installs from TestFlight | ☐ | ☐ |
| **App icon on the home screen looks right** — no artefacts, right at small size | ☐ | ☐ |
| Launches without a crash | ☐ | ☐ |
| Launch screen does not flash something wrong | ☐ | ☐ |
| Opens on the menu, offering the tutorial to a newcomer | ☐ | ☐ |
| Language follows the system language | ☐ | ☐ |
| No missing image, no raw string key anywhere | ☐ | ☐ |

## Tables

| | iPhone | iPad |
|---|---|---|
| 2 players | ☐ | ☐ |
| 3 players | ☐ | ☐ |
| 4 players | ☐ | ☐ |
| 5 players | ☐ | ☐ |
| 6 players | ☐ | ☐ |
| Teams and free-for-all both selectable where they apply | ☐ | ☐ |
| The board reshapes for each — no gaps, no crowding | ☐ | ☐ |

## Opponents

| | iPhone | iPad |
|---|---|---|
| Easy plays, and plays quickly | ☐ | ☐ |
| Medium plays | ☐ | ☐ |
| Hard plays, and thinks for about a second — not longer | ☐ | ☐ |
| No spinner that never ends | ☐ | ☐ |

## Pass and play — the privacy rule

| | iPhone | iPad |
|---|---|---|
| The cover appears before each handover | ☐ | ☐ |
| **No cards are visible while the device is being passed** | ☐ | ☐ |
| Taking the device shows that player's hand and only theirs | ☐ | ☐ |
| A one-person table never asks for a handover | ☐ | ☐ |

## The rules that make Keezen Keezen

| | iPhone | iPad |
|---|---|---|
| Seven split across two pieces | ☐ | ☐ |
| Jack swap | ☐ | ☐ |
| Four backwards | ☐ | ☐ |
| Exact count into home — refused when it overshoots | ☐ | ☐ |
| King and Ace start a piece | ☐ | ☐ |
| **Tapping a highlighted square next to a piece moves — it does not select the piece** (ISS-020) | ☐ | ☐ |

## Saving and coming back

| | iPhone | iPad |
|---|---|---|
| Leave mid-match, return from the menu | ☐ | ☐ |
| Force-quit mid-match, relaunch, resume | ☐ | ☐ |
| The resumed position is exactly where it was | ☐ | ☐ |
| Matches list shows finished and unfinished correctly | ☐ | ☐ |
| Replay plays a finished match back move by move | ☐ | ☐ |

## Everything around the game

| | iPhone | iPad |
|---|---|---|
| Tutorial — all ten lessons reachable | ☐ | ☐ |
| Rulebook opens mid-turn | ☐ | ☐ |
| Settings — sound and haptics switches do what they say | ☐ | ☐ |
| Rotation, both orientations | ☐ | ☐ |
| Split View | — | ☐ |
| Stage Manager, if the device supports it | — | ☐ |

## Feel

| | iPhone | iPad |
|---|---|---|
| Haptics fire on select, place, capture, home, swap, fold, victory | ☐ | ☐ |
| Haptics are not tiring after twenty turns | ☐ | ☐ |
| All seven sounds audible — see `AUDIO_REVIEW.md` | ☐ | ☐ |
| Silent switch silences the game | ☐ | — |
| The player's own music keeps playing | ☐ | ☐ |

## Accessibility

| | iPhone | iPad |
|---|---|---|
| VoiceOver names every card, piece and square usefully | ☐ | ☐ |
| A whole turn can be taken with VoiceOver alone | ☐ | ☐ |
| Dynamic Type at the largest size — nothing unreadable or cut off | ☐ | ☐ |
| Differentiate Without Colour — players still distinguishable | ☐ | ☐ |
| Reduce Motion respected | ☐ | ☐ |
| The action list gives the same moves the board offers | ☐ | ☐ |

## Game Center

| | iPhone | iPad |
|---|---|---|
| Signed in, and the online screen says so | ☐ | ☐ |
| The full online run — see `GAME_CENTER_E2E_CHECKLIST.md` | ☐ | ☐ |
| Achievements appear in Game Center after a solo match | ☐ | ☐ |
| Declining sign-in leaves the rest of the app working | ☐ | ☐ |

---

## Result

```
PHYSICAL DEVICE GATE:  ☐ PASS   ☐ FAIL

Anything that failed, and what it was:
```

A FAIL here is a release blocker. Re-running until green is not a result.
