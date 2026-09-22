# Keezly — the seven sounds, for audition

**Status: SHIPPING IN THE BUNDLE, NOT AUDITIONED BY A PERSON.** Every cue below
exists, plays, and is measured. Whether any of them *sounds right* is a
judgement nobody has made yet, and it is not one a build can make.

Audition them:

```bash
open build/audio-audition
```

Seven WAVs, one per cue, regenerated from the shipping `.caf` files by
`afconvert`. They are byte-for-byte the same audio the app plays — the
conversion is container and encoding only.

To rebuild the shipping files from source instead:

```bash
python3 Tools/soundforge.py && scripts/sounds-build.sh
```

---

## Where the sounds come from

Nothing is sampled and nothing is downloaded. All seven are synthesised by
`Tools/soundforge.py` using modal synthesis — a few inharmonic partials with
different decay rates, which is how a struck object actually behaves. The
provenance of the audio is the source code that made it.

Playback is `AVAudioPlayer` on the **ambient** session category: the silent
switch silences it and the player's own music keeps playing.

---

## The cue list

`FeedbackCue` is one vocabulary for both sound and haptics, so a capture is the
same moment whether it arrives in the ear or in the hand. Cues are driven from
`GameEvent`, not from taps — a capture made by a computer opponent lands exactly
like one you made, and a tap the engine refused makes no sound at all.

| Cue | Fires when | Intended character | Length | Peak | RMS | Haptic |
|---|---|---|---|---|---|---|
| `select` | You pick a card up in your hand | The lightest thing in the set — a fingernail on card stock, over before you notice it | 0.035 s | −17.1 dBFS | −30.8 dBFS | light, 0.25 |
| `place` | A card is played and a piece is set down (`cardPlayed`, `pawnEntered`, `pawnMoved`) | Wood on wood. A piece meeting the board, short and dry | 0.160 s | −9.4 dBFS | −23.3 dBFS | medium, 0.40 |
| `swap` | A Jack exchanges two pieces (`pawnsSwapped`) | Two pieces moving at once — `place` with a second body to it | 0.260 s | −9.9 dBFS | −24.6 dBFS | medium, 0.50 |
| `capture` | A piece is knocked back to its start (`pawnCaptured`) — anybody's, including your own | Harder and brighter than `place`. It should be clear something was taken without being a punishment | 0.300 s | −4.7 dBFS | −18.3 dBFS | rigid, 0.70 |
| `home` | A piece reaches its home lane (`pawnReachedHome`) | Settled. Lower and longer, a piece arriving rather than landing | 0.750 s | −7.5 dBFS | −20.9 dBFS | success |
| `fold` | A hand is thrown in with nothing playable (`handFolded`) | Quiet and flat. A non-event that should not feel like a failure | 0.200 s | −14.4 dBFS | −30.1 dBFS | light, 0.30 |
| `victory` | The match ends (`matchEnded`) | The only cue allowed to be pleased with itself, and the only one over a second | 1.645 s | −4.4 dBFS | −19.9 dBFS | success |

### What the numbers say

The set is deliberately quiet, and deliberately uneven. `select` sits 13 dB
below `capture` because it happens several times per turn and `capture` happens
a few times per match. `victory` is the loudest and by far the longest because
it happens once.

A board game played for an hour is a bad place for a strong haptic: the knock
that feels satisfying on the first move is unbearable on the two hundredth
(§43). The same reasoning caps the audio.

### Bursts

`FeedbackCue.cues(for:)` collapses runs. A Seven split across two pieces is one
decision and produces several move events; buzzing once per square would turn it
into a stutter. When a move both travels and takes something, the louder cue
wins — a move that lands and captures is a capture, and is heard as one.

Two `AVAudioPlayer`s exist per cue and alternate, so a Seven putting two pieces
down in quick succession does not cut its own first knock off.

---

## What is not decided

- **Whether these are the right seven sounds.** They are the right seven
  *moments* — that follows from `GameEvent` and is tested in `FeedbackTests`.
  The character of each recording is an opinion.
- **Whether the relative levels are right on a phone speaker.** They were
  measured, not listened to on hardware.
- **Whether `home` and `victory` are too long** when several pieces come home in
  the closing turns of a match.

Changing any of them is a number in `Tools/soundforge.py` and a rebuild. None of
it touches the engine.
