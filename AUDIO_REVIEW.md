# Audio review — seven cues, on hardware

**Status: TECHNICALLY VERIFIED. HUMAN LISTENING: PENDING.**

Every cue exists, plays, is the right length and sits at a measured level. Not
one of them has been heard by a person on a phone speaker, and no measurement
can decide whether a sound is right.

Listen to them:

```bash
open build/audio-audition
```

Seven WAVs, converted from the shipping `.caf` files by `afconvert` — container
and encoding only, so what you hear is what the app plays. Rebuild the shipping
files from source with `python3 Tools/soundforge.py && scripts/sounds-build.sh`.

---

## How to listen

On the **physical device**, not on the Mac. A laptop speaker flatters a board
game's sounds and a phone speaker does not, and the phone is where they will be
heard.

1. Install the TestFlight build on the iPhone.
2. Settings → Sound and haptics **on**.
3. Play a match and provoke each cue.
4. Then play a second match with the phone at arm's length on a table, which is
   how somebody actually plays it.

The silent switch silences everything: the session is **ambient** on purpose, so
the phone's own music keeps playing and nothing interrupts a podcast.

---

## The seven

| Cue | Fires when | Intended character | Length | Peak | RMS | Technical | Human |
|---|---|---|---|---|---|---|---|
| `select` | A card is picked up | The lightest thing in the set — over before you notice it | 0.035 s | −17.1 dBFS | −30.8 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `place` | A card is played, a piece set down | Wood on wood. Short and dry | 0.160 s | −9.4 dBFS | −23.3 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `swap` | A Jack exchanges two pieces | Two pieces at once — `place` with a second body | 0.260 s | −9.9 dBFS | −24.6 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `capture` | A piece is knocked back | Harder and brighter. Clear something was taken, without being a punishment | 0.300 s | −4.7 dBFS | −18.3 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `home` | A piece reaches its home lane | Settled. A piece arriving rather than landing | 0.750 s | −7.5 dBFS | −20.9 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `fold` | A hand is thrown in | Quiet and flat. A non-event that must not feel like a failure | 0.200 s | −14.4 dBFS | −30.1 dBFS | ✅ | ☐ PASS ☐ REWORK |
| `victory` | The match ends | The only cue allowed to be pleased with itself | 1.645 s | −4.4 dBFS | −19.9 dBFS | ✅ | ☐ PASS ☐ REWORK |

"Technical ✅" means: the file is present in the bundle, 44.1 kHz mono Int16,
loads into `AVAudioPlayer`, and its measured length and level are as listed.

---

## The questions a person has to answer

Ticking PASS on all seven is not the point. These are what the session is for:

1. **Is `capture` satisfying or annoying on the two hundredth move?** It is the
   loudest short cue and it fires often in a six-player match.
2. **Is `select` audible at all** on a phone speaker at arm's length? It is
   13 dB below `capture` deliberately. If it cannot be heard it is doing
   nothing and should either come up or come out.
3. **Is `victory` too long?** 1.6 seconds while the result screen is appearing.
4. **Do `home` and `victory` collide** when the last piece home *is* the win?
5. **Does a Seven split sound like one decision or two?** Runs are collapsed
   and the louder cue wins, and that is worth hearing rather than trusting.
6. **Is the whole set too quiet** in a room with other people in it?

---

## What can be changed, and how cheaply

Every sound is synthesised by `Tools/soundforge.py` — modal synthesis, no
samples, nothing downloaded. Its provenance is the source code that made it.

Changing a level, a length or a brightness is a number in that file and a
rebuild. None of it touches the engine, and none of it needs new assets.

Haptics are a separate channel with the same vocabulary, driven from the same
`FeedbackCue`. If a cue is right in the ear but wrong in the hand, say which —
they are tuned independently (`strength`, and the generator chosen in
`SystemHaptics`).

---

## Result

```
AUDIO REVIEW:  ☐ ALL PASS   ☐ REWORK NEEDED
Date:
Device:
Which cues need rework, and what is wrong with each:
```
