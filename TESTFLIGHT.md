# TestFlight — internal testing

**Status: NO BUILD YET.** The Release workflow exists and will archive to
TestFlight internal testers; nothing has been archived, uploaded or processed.
This describes what happens when it does, and what to test.

**No external beta review.** The archive action distributes `INTERNAL_ONLY`,
which reaches internal testers on the team and starts no Apple beta review. That
is deliberate and is not to be widened without the owner asking.

---

## How a build gets there

```
Keezly Release   (manual trigger)
  → Test      the correctness plan, iPhone 17 + iPad Pro 13-inch
  → Analyze
  → Archive   Release configuration, distribution signing by Xcode Cloud
  → TestFlight, internal testers
```

Build numbers come from `CI_BUILD_NUMBER` via `ci_scripts/ci_pre_xcodebuild.sh`,
written into `Config/BuildNumber.xcconfig` as `CURRENT_PROJECT_VERSION`. They are
monotonic because Xcode Cloud's own counter is, and they never collide with a
number already used — which is the whole reason the local clock is not used
(§105). Marketing version stays `1.0.0`.

---

## What to test — the notes that go with the build

Written for whoever installs it, in the two languages the testers read.

### English

```
Keezly 1.0.0 — first internal build.

Please try, on both iPhone and iPad:

• 2 to 6 players. The board reshapes for each — look for gaps or crowding.
• Pass & play: the screen must be covered before the device changes hands.
  Nobody's cards may be visible while you pass it.
• Computer opponents at easy, medium and hard.
• The awkward cards: a Seven split across two pieces, a Jack swap, a Four
  going backwards, and an exact count into home.
• Tapping a highlighted square NEXT TO a piece must move — not select the
  piece. This was a real bug on iPhone and is the fix most worth checking.
• Online through Game Center: sign in, start a match, take a turn, close the
  app completely, and come back to it.
• Leave a match, force-quit, relaunch, resume. The position must be exactly
  where you left it.
• Tutorial, rulebook, replay of a finished match.
• Sound and haptics, and the switches that turn them off.
• VoiceOver, and the largest Dynamic Type size.

Known and expected:
• An online match earns no achievements. That is deliberate — achievements are
  reported only for a table with one person at it, because a Game Center
  account belongs to one person and a shared device does not.
• There are no leaderboards, and there will not be.
```

### Deutsch

```
Keezly 1.0.0 — erster interner Build.

Bitte auf iPhone und iPad ausprobieren:

• 2 bis 6 Spieler. Das Brett passt sich an — auf Lücken oder Gedränge achten.
• Weitergeben am Tisch: Der Bildschirm muss verdeckt sein, bevor das Gerät
  den Besitzer wechselt. Es darf kein Blatt zu sehen sein.
• Computergegner in leicht, mittel und schwer.
• Die schwierigen Karten: Sieben geteilt auf zwei Figuren, Bube-Tausch, Vier
  rückwärts, exakter Einzug ins Haus.
• Ein markiertes Feld NEBEN einer Figur antippen muss ziehen — nicht die Figur
  auswählen. Das war ein echter Fehler auf dem iPhone und ist die Korrektur,
  die am meisten geprüft werden sollte.
• Online über Game Center: anmelden, Partie starten, ziehen, App vollständig
  beenden, zurückkommen.
• Partie verlassen, App killen, neu starten, fortsetzen. Der Stand muss genau
  dort sein, wo er war.
• Tutorial, Regelbuch, Wiedergabe einer beendeten Partie.
• Ton und Haptik, und die Schalter, die beides abschalten.
• VoiceOver und die größte Schriftgröße.

Bekannt und beabsichtigt:
• Eine Onlinepartie bringt keine Erfolge. Das ist Absicht — Erfolge werden nur
  für einen Tisch mit einer Person gemeldet, weil ein Game-Center-Konto einer
  Person gehört und ein geteiltes Gerät nicht.
• Es gibt keine Bestenlisten, und es wird keine geben.
```

---

## Nothing is claimed that is not in the build

The notes describe only what 1.0.0 does. Online play is named because it ships;
friend invitations are not, because matchmaking is `GKTurnBasedMatch.find` and
inviting a named friend is not implemented.

---

## Internal testers

The group is the owner's to fill — adding a tester sends them an invitation, so
it is not done on his behalf. One action in App Store Connect → TestFlight →
Internal Testing.
