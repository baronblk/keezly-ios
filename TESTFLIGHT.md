# TestFlight — internal testing

**Status: Build 43 ist auf TestFlight.** 1.0.0 (43), am 2026-09-25 lokal
archiviert, signiert, von Apple validiert und hochgeladen.
`processingState = VALID`, `internalBuildState = IN_BETA_TESTING` — für interne
Tester sofort verfügbar.

Build 43 ist **nicht** an die App-Store-Version 1.0.0 gehängt; dort hängt
weiterhin 42. Das ist eine eigene Entscheidung und keine Folge des Uploads.

Vorgänger: 42 (2026-09-23), der Version 1.0.0 zugeordnet. 41 wurde von der
Geräte-QA abgelehnt und ist überholt (`RELEASE_CANDIDATE.md`).

### Was 43 gegenüber 42 bringt

41 Commits, praktisch vollständig Game-Center-Online-Arbeit. Die beiden
Fehler, die ein Online-Spiel vorher unbrauchbar machten:

- **Eine gespielte Karte bewegte keine Figur.** Jede Online-Stellung kommt
  ohne abzuspielende Ereignisse an — sie stammt vom anderen Gerät. Die Hand
  zeichnete sich sofort neu, die Figuren nicht: Karte weg, Figur stehen
  geblieben, bei beiden Spielern, in jedem Online-Zug.
- **Eine Game-Center-Match-ID und eine Keezly-Partie sind nicht dieselbe
  Kennung.** Beide wurden vermischt.

Am Brett, am Menü und an den Karten hat sich nichts geändert:
`MainMenuView.swift` ist seit 42 unverändert, und die einzige Änderung an
`GameScreen.swift` ist der Animations-Bugfix oben.

**Der Build ist nicht Internal Only.** `externalBuildState` ist
`READY_FOR_BETA_SUBMISSION`, der Export lief mit
`testFlightInternalTestingOnly=false`. Er ist damit auch für eine externe
Beta und für die Prüfung brauchbar. Eine externe Beta zu *starten* ist eine
Eigentümerentscheidung und wird nicht im Vorbeigehen getroffen.

---

## How a build gets there

Für 1.0.0 (42) und (43) **nicht** über Xcode Cloud, sondern lokal:

```
xcodebuild archive      Release, generic/platform=iOS
xcodebuild -exportArchive   app-store-connect, signingStyle=automatic
altool --validate-app   VERIFY SUCCEEDED with no errors
altool --upload-app     Delivery UUID e00555f2-… (43)
App Store Connect       processingState VALID, IN_BETA_TESTING
```

Der Cloud-Weg endet weiterhin an einem Apple-seitigen Signaturfehler (90035,
NFC/NFD im Zertifikatsnamen) und an einem blockierten Session-Proxy beim
Upload. Beides ist in `RELEASE_CANDIDATE.md` und `XCODE_CLOUD.md` belegt. Der
Cloud-Weg für Build, Test und Analyze bleibt gültig und wird weiter benutzt.

Der ursprünglich geplante Weg, sobald Apple den Signaturfehler behebt:

```
Keezly Release   (manual trigger)
  → Test      the correctness plan, iPhone 17 + iPad Pro 13-inch
  → Analyze
  → Archive   Release configuration, distribution signing by Xcode Cloud
  → TestFlight
```

Build numbers come from `CI_BUILD_NUMBER` via `ci_scripts/ci_pre_xcodebuild.sh`,
written into `Config/BuildNumber.xcconfig` as `CURRENT_PROJECT_VERSION`. They are
monotonic because Xcode Cloud's own counter is, and they never collide with a
number already used — which is the whole reason the local clock is not used
(§105). Marketing version stays `1.0.0`. Ein lokaler Archive-Lauf setzt die
Nummer von Hand auf die nächste freie und muss dieselbe Monotonie einhalten;
42 folgt auf 41.

---

## What to test — the notes that go with the build

Written for whoever installs it, in the two languages the testers read.

### English

```
Keezly 1.0.0 (42).

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

Fixed since build 41, and worth attacking on purpose:
• Starting an online match with 3 or 5 seats crashed the app. Try every seat
  count, and switch between them before you start.

Known:
• An online match earns no achievements. Not because it cannot — an online
  seat belongs to exactly one Game Center account — but because the reporting
  was never wired up for online matches. See GAME_CENTER_ACHIEVEMENTS_ONLINE.md.
• There are no leaderboards, and there will not be.
```

### Deutsch

```
Keezly 1.0.0 (42).

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

Seit Build 41 behoben, bitte gezielt angreifen:
• Eine Onlinepartie mit 3 oder 5 Sitzen ließ die App abstürzen. Bitte jede
  Sitzzahl probieren und vor dem Start zwischen ihnen hin- und herschalten.

Bekannt:
• Eine Onlinepartie bringt keine Erfolge. Nicht, weil sie es nicht könnte —
  ein Onlinesitz gehört genau einem Game-Center-Konto — sondern weil die
  Meldung für Onlinepartien nie verdrahtet wurde. Siehe
  GAME_CENTER_ACHIEVEMENTS_ONLINE.md.
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
