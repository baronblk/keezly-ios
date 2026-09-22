# Keezly — Privacy

**Keezly collects nothing.**

Not a reassuring summary of a longer document that says otherwise — the whole
fact. There is no account, no analytics, no advertising identifier, no crash
reporter, no third-party SDK, and no network code in the shipping app at all.
Turning off aeroplane mode changes nothing about how Keezly behaves, because
there is nothing for it to connect to.

This file is the source for the privacy text the App Store listing points at,
and for the App Privacy answers somebody has to give in App Store Connect under
their own name (MAN-13).

---

## What the app stores, and where

Everything Keezly keeps is on the device, in the app's own container, and goes
away when the app is deleted.

| What | Where | Why |
|---|---|---|
| Sound and haptics switches | `UserDefaults` | So a preference survives a restart |
| Whether the welcome screen has been seen | `UserDefaults` | So it is not shown twice |
| Saved matches | The app's Application Support directory | So a match can be resumed, replayed and counted in the statistics |

A saved match is a **seed and a list of accepted actions** — the two things
that reproduce a game exactly — together with the table's settings, a match id
and two times.

The match id is a `UUID` made when the match is dealt. It identifies that
match, not a device and not a person: it is not the identifier for vendors, not
an advertising identifier, and nothing derived from the hardware. The two times
are when the match was dealt and when an action was last added, in whole
seconds, which is what lets the history list show the most recent match first
and offer to resume it.

There is no name anywhere in it. Seats are numbers.

Statistics are **derived** from those saved matches when the screen is opened.
They are not a second record kept beside the matches, so deleting a match
removes it from the statistics too, by construction rather than by remembering
to.

---

## What the app does not do

- No network requests. No servers, ours or anybody's.
- No advertising, and no advertising identifier is read.
- No analytics, telemetry, crash reporting or session recording.
- No contacts, photos, location, microphone, camera, calendar or health data.
  None of those permissions is requested, because none of them is used.
- No third-party SDKs. The only dependency is `KeezlyCore`, which is part of
  this repository and is deliberately framework-free (DEC-001).
- Nothing is shared with anyone, because there is nothing to share and nobody
  to share it with.

---

## Game Center

Keezly is built with Game Center achievements worked out locally, by replaying
a finished match and reading the engine's own events. **Nothing is reported
anywhere yet** — that needs an App Store Connect record the app does not have
(MAN-02, MAN-05).

If and when reporting is enabled, Game Center is Apple's service and Apple's
privacy policy governs what it does with a player's identity. Keezly would send
it achievement completion and nothing else. There are deliberately **no
leaderboards**: online results cannot be ranked honestly while a modified
client can read every hand (DEC-025), and a leaderboard implies a fairness
guarantee this software cannot keep.

---

## Children

Keezen is a family board game and children will play it. That is a reason to
have written the two lists above the way they are, not a reason for a separate
policy: there is no data collection to limit, no advertising to age-gate and no
communication feature to moderate.

---

## The privacy manifest

`App/Keezly/PrivacyInfo.xcprivacy` declares the one required-reason API Keezly
uses: `UserDefaults`, under `CA92.1` — information accessed by this app, stored
by this app, read from nothing else. Tracking is declared false, the tracking
domain list is empty, and the collected-data list is empty, each because it is.

---

## Changes

If Keezly ever does collect something, this file changes first and the change
is in the repository history where anybody can read it.
