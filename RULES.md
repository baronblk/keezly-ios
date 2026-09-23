# Keezly — Rules

The rules as Keezly implements them, written from scratch. Where a rule has
known variants, the variant, its reasoning and its configuration switch are in
`RULE_VARIANTS.md`.

This file describes **Keezly Classic**, the default preset.

---

## Goal

Be the first to bring all four of your pawns from your waiting area, all the
way around the board, into your own home lane. In team play, a team wins only
once *both* partners have finished.

---

## Setup

- 2 to 6 players. Every player owns four pawns and one coloured seat.
- All pawns start in their owner's waiting area.
- The board is a single shared track. Each player contributes 16 squares to it,
  so a four-player board has 64 track squares. Each player also has four private
  home squares.
- Each player has one **start square** on the track, and enters the track there.
- The **home entry** is the square immediately before your own start square:
  you travel almost all the way around and then turn into your home lane.
- Play moves clockwise.

---

## Cards

The deck holds a complete run of ranks — A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K —
once per player. Two players use 26 cards, four use 52, six use 78. Suits are
printed for looks only and never affect a rule. There are no jokers.

Cards are dealt in three rounds of **5, then 4, then 4** cards each, thirteen
per player in total, which uses the deck up exactly. Then the cards are
gathered, shuffled, the dealer moves one seat clockwise, and a new cycle begins.
The player to the dealer's left plays first.

---

## What the cards do

| Card | Effect |
|---|---|
| **A** | Move a pawn from your waiting area onto your start square, **or** move one square forward |
| **K** | Move a pawn from your waiting area onto your start square |
| **Q** | Move 12 squares forward |
| **J** | Swap one of your pawns on the track with another player's pawn on the track |
| **10, 9, 8, 6, 5, 3, 2** | Move that many squares forward |
| **7** | Seven steps in total — all with one pawn, or split across two pawns |
| **4** | Move exactly 4 squares **backward** |

---

## Moving

A pawn moves forward around the track and, on reaching its own home entry,
turns into its home lane. A pawn in the waiting area can only be brought out by
an Ace or a King.

### Direction — the canonical statement

**The Four is the only card in the game that moves a pawn backward.** Every
other rank that moves a pawn moves it forward, and the Seven moves it forward on
every one of its partial legs, never only in the total. The Jack does not move
pawns at all; it exchanges two of them, so neither one travels.

"Forward" is measured as the pawn's own **progress**: how far it has come along
its route from its start square towards its home. It is deliberately not the
global track index, because the track is a ring — a smaller index is not
"behind" a pawn once it has wrapped, and a pawn entering its home lane leaves
the track's numbering entirely.

This is one rule in one place. `MoveGenerator` is the sole authority on what is
legal (DEC-004); the UI filters `observation.legalMoves` and takes its target
squares from `observation.preview(move)`, so it cannot construct a move the core
did not offer. There is no second movement calculation anywhere in the app, and
`MoveDirectionTests` holds the statement above to the code for every rank at
every table size from two to six seats, including the wrap-around and the home
entry.

### Blockades

A pawn standing on **its own start square is protected**. It cannot be captured,
it cannot be passed by any pawn — in either direction — and a Jack cannot take
it. It is a real roadblock, including for your own pawns.

If your own start square is occupied by one of your own pawns, you cannot bring
another pawn out until it moves on.

### Capturing

Landing exactly on an unprotected pawn sends that pawn back to its owner's
waiting area.

This includes your own pawns and your partner's. Because of the forced-move
rule below, you can be compelled to knock out your own partner. That is part of
the game.

---

## The forced move

**If you have any legal move, you must play one.** Even a move that hurts you.
You may not pass to keep a good card.

If — and only if — not a single card in your hand produces a legal move, you
throw in your whole hand. You then sit out the rest of this deal round and wait
for the next one.

---

## The Seven

A Seven is worth exactly seven steps. You may:

- move one pawn all seven squares, or
- split the seven across **two** pawns: 1+6, 2+5, 3+4, or those the other way round.

All seven steps must be used, and each part must be legal on its own, in the
order you play them. If no combination works, the Seven cannot be played at all.

In team play the Seven has one more trick: if the first part brings your last
remaining pawn home, the remaining steps may be played with a pawn belonging to
your partner.

---

## The Jack

A Jack swaps one of your pawns on the track with a pawn belonging to another
player on the track. In team play your partner's pawn is a valid target too.

Pawns in a waiting area, pawns in a home lane, and pawns protected on their own
start square can never be swapped.

---

## The Four

A Four moves a pawn exactly four squares backward along the track.

It never enters a home lane and never takes a pawn out of one. It cannot cross a
protected start square. Used well it is one of the fastest ways to reach your
own home entry — moving backward past your start square puts you close to it.

---

## Home

Your four home squares are safe. A pawn in your home lane cannot be captured or
swapped.

- You need an **exact** count to land on a home square.
- You may never jump over a pawn that is already home.
- A count that would overshoot the last home square is not a legal move.

---

## Teams

With 4 players the default is two teams of two; with 6 players, three teams of
two. Partners always sit opposite each other.

Once all four of your own pawns are home, you keep playing — with your partner's
pawns. Your team wins when every one of its players has finished.

With 2, 3 or 5 players everyone plays for themselves, and free-for-all is also
available as an option at 4 and 6 players.

---

## Leaving a match

In team play, resigning forfeits the match for your team. In free-for-all you
are removed from the race, your pawns leave the board, and the remaining players
play on; the last one still in wins.
