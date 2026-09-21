# Keezly — Achievements

The ten achievements Keezly awards, what each one takes, and how it is worked
out. Registered with Game Center under MAN-06; **none of them has been verified
against a real Game Center account**, because the App Store Connect record does
not exist yet (MAN-02).

---

## How an achievement is decided

Not by counting as it happens. `AchievementEvaluator` takes a **finished
`MatchRecord`**, replays it through the real engine, and watches the
`GameEvent`s go past — the same events the board animates.

Three things follow from that, and all three are the point:

- **There is no tally to drift.** A crash between the move and the increment,
  a match deleted, a save that failed — none of them can leave a counter
  claiming something the matches do not support.
- **It is recomputable.** The same record earns the same set today and in a
  year. If the evaluator changes, every past match can be re-evaluated.
- **No view decides anything.** A screen displays what the evaluator returned.

An **abandoned match earns nothing**. Leaving a game halfway is not an
accomplishment, and counting it as one would make the rest of the set
meaningless.

---

## The set

Identifiers are published names: once a player has earned one, renaming it
loses their progress. They are written out in full in `Achievement.swift`
rather than derived.

| Identifier | Points | Earned by | Decided from |
|---|---|---|---|
| `…achievement.finished` | 5 | Play a match through to its end | The record's status is `completed` |
| `…achievement.won` | 10 | Win a match | The seat is in `GameResult.winningSeats` |
| `…achievement.untouched` | 20 | Win without ever being knocked back | Won, and no `pawnCaptured` event names one of the seat's own pieces |
| `…achievement.split` | 10 | Split a seven across two pieces | A `cardPlayed` of rank seven in the same turn as moves of two different pieces |
| `…achievement.swapped` | 5 | Swap two pieces with a jack | A `pawnsSwapped` whose first piece belongs to the seat |
| `…achievement.backwards` | 5 | Send a piece backwards with a four | A `pawnMoved` with `backward: true` |
| `…achievement.knockout` | 5 | Knock somebody else's piece back | A `pawnCaptured` by the seat, of a piece that is **not** the seat's own |
| `…achievement.resilient` | 15 | Win after being knocked out at least once | Won, and at least one `pawnCaptured` named one of the seat's pieces |
| `…achievement.fullTable` | 10 | Play a six-player match to the end | `seatCount == 6` and the record is `completed` |
| `…achievement.partners` | 15 | Win playing in a pair | Won, and `teamMode == .teamsOfTwo` |

**Total: 100 points.** Game Center allows a thousand. A hundred is a set of
things worth doing rather than a list worth a point each.

`untouched` and `resilient` are opposites and can never both be earned in one
match; `AchievementTests` asserts that across five seeds and every seat.

### Why these ten

They are things a player would recognise having done. "Play 500 matches" is a
measure of endurance rather than of anything that happened at the table, and
Keezen has enough luck in it that most such targets say more about the deal
than about the player (§30).

Knocking out **your own partner** earns nothing. The forced-move rule (§13)
means it is sometimes unavoidable, and congratulating somebody for it would be
the app misreading the game.

---

## Verification status

| | |
|---|---|
| The evaluator | **VERIFIED** — `AchievementTests`, nine tests over real played-out matches at four and six seats, in pairs and free-for-all |
| The identifiers, points and text | **DESIGN IMPLEMENTED** — registered here, not yet in App Store Connect |
| Reporting to Game Center | **NOT IMPLEMENTED** — blocked on MAN-02, then MAN-05 and MAN-06 |
| End-to-end award on a device | **BLOCKED** — needs a real Game Center account |

Nothing in Keezly currently reports an achievement anywhere. The evaluator is
built, tested and ready; the reporting is one call per achievement once the
account exists, and until then claiming otherwise would be exactly the kind of
"implemented" that means nothing.
