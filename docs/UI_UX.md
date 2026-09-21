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

## A quiet Dutch identity (DEC-019)

Keezen is Dutch. The board says so without saying it loudly: **ornament, never
illustration.** No windmills, no clogs, no tulip fields, no flags — those would
make a souvenir out of a board meant to look like a good one.

| Where | What |
|---|---|
| The rim | A running border between two fine incised lines: an abstracted tulip alternating with a concave lozenge |
| The middle | A medallion framing the cards, one petal in each gap between the home lanes |
| Each home lane | A small chevron at its inner end, pointing the way the pawns travel |
| One place only | A single orange keystone at the top of the medallion |

**Engraved, not printed.** Every ornament is drawn the way a milled hole is
drawn: a lit lip beneath a dark incision. That one shared trick is what makes
it belong to the board rather than sit on it. The blue is Delft, at low
opacity, and it is never a player colour — those stay independent.

**Its own geometry.** One leaf construction, used at three sizes, plus one
lozenge. No tile pattern, border or board graphic is traced from anywhere; the
tradition is the inspiration, the shapes are Keezly's.

Three things it has to survive, each of which changed the design:

- **Never mistakable for a playing square.** A test measures every motif
  against every square at every seat count. The first attempt collided with the
  waiting trays — so the rim was *widened* rather than the ornament squeezed
  into the gap. The playing area is about six percent smaller as a result, and
  that is the price of a frame that can carry a border.
- **It has to be small and still read.** The first tulip — a bud with curling
  side strokes and a stem — came out as a stray squiggle at the size it is
  actually drawn. Three symmetric leaves survive. Below about nine points per
  square the motifs are dropped and only the border lines remain: a phone gets
  the frame, not the detail.
- **It has to fit every table.** The medallion is measured against the board's
  inner field rather than in square widths. At two seats the home lanes reach
  almost to the middle and there is no quiet centre at all, so nothing is drawn
  (ISS-008). Ornament over the game is worse than no ornament.

---

## The polish pass (DEC-021)

The direction was already settled; this was depth and balance, not a redesign.

| Area | What changed |
|---|---|
| **Holes** | A shadow cast down by the far rim, a floor that darkens towards the near one, and a brighter lit lip. Three shadings, no gloss — the track reads as drilled wood, and the lane is markedly easier to follow |
| **Player colours** | Home lanes and waiting trays carry more of the seat's colour, home squares are tinted so they are never mistaken for track, and a start square gets a halo under its ring |
| **The middle** | The medallion drops to about half its former weight so it sits *behind* the cards, and the pile, the turn and the round have room to read as three things |
| **The edge** | A lit-to-shaded bevel just inside the rim, and two shadows — a tight contact one and a wide soft one — so the board sits on a dark table rather than floating |
| **Ornament** | The running border is a little clearer, the medallion a good deal quieter. No new motifs |
| **Seat panels** | Made of the board's own wood rather than grey system material, with the seat's mark set in as a seal. They belong to the table now |
| **Cards** | A faint sheen across the stock, a deeper red, a two-line selection border in the card's own ink, and a two-part shadow so a chosen card lifts |

**Air, in the right amount.** The first attempt at calming the middle doubled
the spacing, and the labels floated away from the cards they belong to. The
middle has to read as one group of three things, not three separate ones.

### Three layout defects the pass uncovered

Screenshots taken for a design review are worth more than the review:

- **The board could be drawn wider than the screen.** Its size came from the
  height alone, so in portrait it was clipped. It is now bounded by both
  dimensions.
- **The far seat panel hung off the right edge**, twice: first because the
  padding was left out of the width budget, then because the columns were
  measured against the raw screen width. Everything is now derived from the
  width that is actually free.
- **Two cards were cut off at the edges of a phone.** A fanned card is rotated
  about its foot and reaches further sideways than the frame it is given, so
  the hand is now given a frame narrower than the screen by more than its
  padding.

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

## Pointer and keyboard (M4.7, DEC-020)

Touch stays the complete way to play. The pointer and the keyboard are added
without taking anything from it (§46).

**Focus is not selection.** Selection is what the player has chosen and the
engine will act on. Focus is only where the keyboard is pointing. Conflating
the two is how keyboard support ends up changing the game by accident.

| Key | What it does |
|---|---|
| Left / right | Walks the current band — the hand, the pieces, or the squares — wrapping at its ends |
| Up / down | Crosses between those bands |
| Return / space | Acts on what is focused |
| Escape | Cancels, exactly as tapping a chosen card again does (§37) |

**Only live things are reachable.** A card with no legal move is shown so the
player can see why they are stuck, but the keyboard steps over it — a dead end
a pointer user never meets. Squares are walked in a fixed order — round the
track, then home, then the waiting area — because a `Set` has none, and without
one the keyboard would wander differently on every render.

**The focus ring is black and white**, two concentric strokes, so it reads on
the cream of a card and on the wood of the board, and so it never depends on
colour (§42). A focused card comes forward, or its neighbour would cover the
ring.

**The pointer lifts what can be acted on** and highlights squares. It is
attached only where a tap would do something: a pointer that lifts a card the
engine will refuse is a promise the game cannot keep.

**What is verified, and what is not.** The decision logic is pure and unit
tested. Focus behaviour is simulator-verified. Whether a key press arrives is
**not verified**: iOS gives a view focus only when a hardware keyboard or Full
Keyboard Access is present, and neither a keyboardless simulator nor this
machine can supply one. The tests that need real keys skip rather than pass.

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
| Free-for-all table (no partner badge) | SIMULATOR VERIFIED |
| Five-player table | SIMULATOR VERIFIED |
| A Jack with its swap targets | SIMULATOR VERIFIED |
| A Seven mid-split | SIMULATOR VERIFIED |
| Phone mid-match | SIMULATOR VERIFIED |
| iPhone 17 Pro, iOS 27.0 | PHYSICAL DEVICE VERIFIED — 58/58 |
| iPad (A16), iOS 27.0 | PHYSICAL DEVICE VERIFIED — 58/58 |

### Open

- Dealing, the Seven's legs and the Jack swap have no bespoke choreography
  beyond the generic move and swap.
- Haptics and audio are not implemented.
- Dark Graphite is not offered in Settings.
- Split View and Stage Manager are untested.
- Landscape captures come out rotated (ISS-009) — fine for review, not
  submittable as App Store screenshots.
- A two-player table has not been reviewed for crowding in the middle.
