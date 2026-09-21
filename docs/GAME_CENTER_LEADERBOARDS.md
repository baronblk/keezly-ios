# Keezly — Leaderboards

**There are none, and that is a decision rather than an omission.**

---

## Why not

A leaderboard is a claim: that the numbers on it were earned under conditions
comparable enough to be ranked against each other. Keezly cannot make that
claim about online play, and says so rather than ranking anyway.

`DEC-025` records the finding in full. In short: Game Center match data carries
the seed and the accepted actions, because that is what makes a match
reproducible on every device. Reproducing the match reproduces the deal — so a
**modified client can read every hand and the order of the remaining deck**.
Keezly's own interface and its own agents respect hidden information completely
and are tested to; a client somebody else has changed is not something Keezly
can constrain.

Ranking players on results produced under those conditions would be publishing
a table that the game cannot stand behind.

## What about local play?

Also no, for a different and smaller reason. Local results are honest, but
Keezen is a family game with a great deal of luck in it. A ladder built on
fifty matches against a computer opponent would mostly be reporting the deals
(§30). The **match history and statistics** show what has actually happened on
the device, which is the true version of what a leaderboard would be pretending
to say.

## What would change this

A future competitive variant — with either a server-authoritative architecture
or a correct multi-party protocol behind it, as DEC-025 sets out — could carry
leaderboards honestly. That is its own piece of work and its own decision, not
a switch to be turned on here.

## Status

| | |
|---|---|
| Leaderboards in 1.0.0 | **NOT BUILT — deliberate** (DEC-025) |
| MAN-06 | Covers achievements only |
