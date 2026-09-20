# Keezly — UI and UX

The design system, the board, the cards and the interaction flow. Decisions
that shaped them are in `DECISIONS.md`; this describes what exists.

---

## Direction

**Tactile digital board game.** Not flat business UI, and not a casino game.
The test a screen has to pass is whether an iPad on the table reads as *a good
board game lying there* (DEC-018).

The reference for materiality is a well-made physical Keezen board: warm wood,
holes milled into it, pieces with weight, real playing cards. What is taken
from that reference is the *feel*. Nothing is traced from it: every board
graphic, card face, piece silhouette and pattern in Keezly is drawn from our
own geometry (§76).

---

## Material — Classic Wood

`BoardTheme` carries the material, so a second one can be added without
touching the renderer. Classic Wood is the default and the quality bar for
1.0.0; Dark Graphite exists in the type and is not yet offered in Settings.

A theme is **not** an appearance. Classic Wood is the same board in light and
dark mode — the asset catalogue simply dims it, the way a real board is dimmer
in a dim room.

| Element | Treatment |
|---|---|
| Panel | Light maple; a top-to-bottom sheen; a milled edge with a thin lit rim |
| Grain | Sparse wandering streaks, one to three hole-widths apart, at 4–7 % opacity |
| Hole | Dark floor, shadow under the upper rim, **lit lower lip** |
| Home lane | A rounded colour inlay under the four home holes |
| Waiting area | A shallow colour tray beside each seat's start |
| Start square | Its hole carries a ring in the seat's colour — a pawn there is untouchable and blocks the track (§15) |
| Centre | Two faint concentric rings. Not a logo: the board should look like a board, not a dashboard |

The lit lower lip is what does the work. Without it a hole is a dark dot
painted on; with it, the eye reads a cavity.

**An earlier attempt drew grain as evenly spaced full-width curves every half
hole.** It read as ruled notepaper. Wood grain is irregular, widely spaced and
almost invisible; what sells it is that the eye cannot quite resolve it.

---

## Board geometry

`BoardLayout` maps `BoardPosition` to coordinates. `KeezlyCore` holds no
geometry at all (DEC-001), so this is the only place that decides where a
square is.

- The track sits on a **superellipse** (exponent 8): straight runs of holes
  with soft corners — the traditional form, from our own curve (DEC-017).
- Holes are placed at equal **arc length**, not equal angle. On a squared ring
  those differ sharply; equal angle would crowd the corners. Tested directly,
  including against the angular alternative.
- Home lanes run from each seat's entry straight towards the centre, so every
  seat's lane is the same length and sits the same way relative to its side.
- **Seat 0's home lane comes up from the near edge**, where the local player
  sits.
- Everything is parametric over 2–6 seats. There is no hard-coded board.

---

## Pieces

A classic pawn — round head, collar, flared body — as our own silhouette (§44).
Depth is a gradient, one specular highlight and a contact shadow: enough to
read as an object, short of pretending to be a photograph.

Each piece is anchored so its **base sits in the hole** while its head rises
above the board, as a real piece does.

**Colour is never the only signal** (§42). Every seat also carries a distinct
geometric mark — circle, triangle, square, diamond, hexagon, chevron — stamped
on the body. The board stays readable without colour vision, in greyscale, and
in a screenshot printed in black and white.

| Seat | Colour | Mark |
|---|---|---|
| 0 | red | circle |
| 1 | blue | triangle |
| 2 | amber | square |
| 3 | green | diamond |
| 4 | violet | hexagon |
| 5 | orange | chevron |

States are shown by ring and lift, never by hue alone: *selectable* draws a
warm ring, *selected* draws the target-green ring and raises the piece.

---

## Cards

A player's first thought must be "that is a playing card", not "that is a
button with a letter on it" (§45).

- Cream face, fine border, continuous rounded corners, a soft shadow.
- **Classic corner indices**: rank over suit, top-left and repeated rotated at
  bottom-right. This is what makes a fanned hand readable — only the top-left
  corner needs to be visible.
- **Traditional pip layouts** for 2 through 10, with the lower half rotated as
  on a real card. The Ace carries one large pip.
- Suits are drawn as geometry, not shipped as glyphs, so they scale from a
  corner index to a centre pip without going soft.
- Hearts and diamonds red, spades and clubs dark. **This carries no rule
  meaning and the engine never sees it** (§10).

### Court cards

Traditional court illustrations are somebody's artwork; these are not them
(§76). Keezly draws its own reduced emblem — a stepped crown for the King, a
coronet for the Queen, a plume for the Jack — mirrored top and bottom the way a
real court card is, in the suit's colour.

### The Keezen function

What Keezen adds to a card — a Four moves backward, a Seven splits — is a small
mark in the free top-right corner, where a real card has nothing. Secondary by
construction: it never competes with the index.

| Card | Mark | Meaning |
|---|---|---|
| A | `⌂1` | Bring a pawn out, or move one |
| K | `⌂` | Bring a pawn out |
| Q | `12` | Twelve forward |
| J | `⇄` | Swap |
| 4 | `←4` | Four backward |
| 7 | `1–7` | Seven steps, split across one or two pawns |

### Card back

A lattice of small diamonds around a quiet centred ring. Symmetrical in both
axes, so it looks right whichever way a card is dealt, and legible at the size
of a draw pile.

### Unplayable cards

Dimmed, never erased. A player who cannot move needs to see *which* cards are
stuck, not an empty space where their hand was (§36).

---

## The hand

Cards overlap and fan, each tilted a little more than the last, so the hand
reads as one object. The chosen card straightens, lifts and comes forward — the
gesture a person makes with real cards.

When space runs short **the fan tightens; the cards do not shrink**. A card too
small to read is worse than a card partly covered, and the corner index means a
covered card is still identifiable.

Cards are larger on iPad (112 pt) than on iPhone (72 pt): the large display is
the point, not a bonus (§4).

---

## Layout

Adaptive by size class, not by device name.

**Regular width (iPad, and especially landscape).** The board is square, so its
size is set by the height left after the hand. Whatever width that leaves goes
to the **seat status panels** on either side rather than sitting empty beside a
centred board. Each panel carries the seat's colour and mark, its name, how
many cards it holds, how many pawns are home, whether it deals, and whether it
is on turn (§35).

**Compact width (iPhone).** Not the iPad layout scaled down. Two defects made
the difference concrete:

- **Six seat panels across a phone** forced the names to wrap and pushed the
  layout wider than the screen, which clipped the board. Phones show compact
  **chips** that drop the name entirely — colour and mark already identify a
  seat, and identify it the same way on the board, so nothing is lost.
- **A phone in landscape can report a regular width.** Deriving the board size
  from the height left after the hand produced a 149-point board on a
  393-point screen. The layout is now chosen by the space actually available:
  below 520 points of height a short-and-wide arrangement gives the board the
  full height and puts the hand beside it.

A square board on a tall phone is limited by width, which leaves height to
spare. It goes to the cards.

**Dynamic Type.** The interface used fixed font sizes throughout, so the
reader's setting had no effect at all — an accessibility failure, not a rough
edge (§53). The distinction that resolves it: **chrome text follows the reader,
card ranks and pips follow the card.** A rank that outgrew its card would be
less readable, not more. Seat panels, chips, the turn indicator and the deal
label scale; at an accessibility size the board's labels wrap rather than
truncate, because half a sentence tells the reader nothing.

---

## Animation

Event-driven (§39). `GameState` is final before the first frame; the presenter
only shows how the board got there.

- A pawn **visits every square it passes**, which is also how a player checks
  that the engine did what they expected.
- A **capture is shown after the move that caused it**. The engine emits it
  first, because the square must be vacated before the mover can take it; drawn
  in that order it reads as a piece flying off before anything hits it. The
  reordering is presentation only and touches nothing in the engine.
- A **swap** moves both pieces at once.
- **Reduce Motion** lands moves instead of walking them.
- **Any interruption settles on the truth.** Cancelling, leaving the foreground
  and dismissing the screen all end with the board showing the real position,
  because the settle sits in a `defer`. Verified by removing it and watching
  three tests fail.

The presenter holds its own copy of the pawn positions and has no access to
`GameState`, so no animation can change the game.

---

## Interaction

The flow is card → pawn → square (§36). Illegal targets are never offered:
`PlayPlanner` derives every highlight from the engine's **complete** legal
moves.

That is what makes the Seven safe (§38). A player can only commit a first leg
that some complete legal sequence starts with, so it is impossible to spend
three steps and discover the remaining four are unplayable. The remaining steps
are shown as a small progress row.

Tapping a selected card again clears it: cancelling before a move is final must
always be possible (§37).

**Input is closed while the board catches up.** The state is authoritative the
instant the reducer returns; every submission carries the revision it was made
against, so a second tap cannot apply a move twice (§63). Covered by a UI test
that double-taps deliberately.

---

## Verified

Screenshots are captured by `DesignReviewScreenshots`, which launches the app
in a deterministic mode with a fixed seed and seat count (§87), so the same
board comes out every run.

Status terms are kept apart on purpose (§167): **DESIGN IMPLEMENTED** means it
exists in code, **SIMULATOR VERIFIED** means it was built and tested on a
simulator, **PHYSICAL DEVICE VERIFIED** means it was built and tested on real
hardware.

| Screen | Status |
|---|---|
| iPad 13" landscape, 4 and 6 players | SIMULATOR VERIFIED |
| iPad 13" portrait, 4 players | SIMULATOR VERIFIED |
| iPhone portrait, 4 and 6 players — smallest, standard and largest | SIMULATOR VERIFIED |
| iPhone landscape | SIMULATOR VERIFIED |
| Accessibility text size (extra large) | SIMULATOR VERIFIED |
| iPhone 17 Pro, iOS 27.0 | PHYSICAL DEVICE VERIFIED |
| iPad hardware | **BLOCKED** — no physical iPad paired (MAN-10) |

### Open

- Dealing, the Seven's legs and the Jack swap have no bespoke choreography
  beyond the generic move and swap.
- Haptics and audio are not implemented.
- Dark Graphite is not offered in Settings.
- Split View and Stage Manager are untested.
