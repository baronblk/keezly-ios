# Achievements in Onlinepartien — Befund und getroffene Entscheidung

**Anlass:** die Annahme „Onlinepartien bringen nie Erfolge" wurde hinterfragt.
Sie hält der Prüfung nicht stand, und das ist hier belegt statt behauptet.

**Entscheidung des Owners vom 2026-09-24: B.** Onlinepartien melden dieselben
passenden Achievements wie lokale Partien, ausschliesslich für den eigenen Sitz.
Keine Bestenlisten, DEC-025 bleibt vollständig bestehen. Umgesetzt in `b03ed53`,
enthalten ab **Build 43**.

---

## Die Zuordnung ist eindeutig beweisbar

Anders als bei Pass & Play. Die Kette im Code, Glied für Glied:

```
OnlinePlay.authenticate()
    → GKLocalPlayer.local.gamePlayerID                (der angemeldete Account)

OnlinePlay.client
    → OnlineMatchClient(participantID: authentication.playerID)

OnlineMatchRun.init
    → mySeat = match.participants.seat(of: me)        (me == participantID)

MatchSession(online:mySeat:)
    → roles[mySeat]  = .human
      roles[andere]  = .remote
```

Daraus folgt zwingend:

| | |
|---|---|
| `humanSeats` | genau **ein** Sitz |
| `isPassAndPlay` | **false** |
| `localSeat` | **der Sitz des angemeldeten Game-Center-Accounts** |

Ein Onlinesitz gehört also nachweislich genau einer authentifizierten Person —
genau das, was bei Pass & Play fehlt und was dort die Zurückhaltung
rechtfertigt. **Die Begründung „ein Game-Center-Konto gehört einer Person, ein
geteiltes Gerät nicht" trifft auf Online gerade nicht zu.**

## Der Evaluator würde korrekt antworten

`MatchSession.achievementsEarned`:

```swift
guard result != nil, !isPassAndPlay, let seat = localSeat else { return [] }
return AchievementEvaluator.unlocked(in: record, for: seat)
```

Für eine beendete Onlinepartie sind alle drei Bedingungen erfüllt. Der Aufruf
liefert die korrekt zugeordnete Menge.

## Gemeldet wird trotzdem nichts

```swift
init(online match: OnlineMatch, mySeat: Seat) {
    ...
    achievements = nil          // ← hier endet es
}
```

`OnlineMatchRun` enthält **keine einzige** Referenz auf Achievements (geprüft:
null Treffer). Es gibt also keine Regel „Online meldet nicht" — es gibt eine
Auslassung.

---

## Was das bedeutet

| | |
|---|---|
| Technisch möglich | **ja**, ohne neue Zuordnungslogik |
| Aktuell implementiert | **nein** |
| Ursache | Auslassung, nicht Entwurf |
| Aufwand | `achievements` durchreichen und nach `noteResult` melden |

Der frühere Kommentar im Code und die TestFlight-Notiz begründen das Verhalten
mit der Pass-&-Play-Attribution. Diese Begründung ist für Online **sachlich
falsch** und muss so nicht stehen bleiben.

---

## Entscheidung: B — umgesetzt

Der Owner hat B gewählt: Onlinepartien melden Achievements.

| | |
|---|---|
| Gemeldet wird | ausschliesslich `mySeat` |
| Zuordnung | `mySeat` **ist** `GKLocalPlayer.local` — siehe die Kette oben |
| Bedingungen | dieselben wie lokal; **ein** Evaluator, keine Online-Sonderregel |
| Für den Gegner | **nie** — jeder andere Sitz ist `.remote`, `localSeat` ist `mySeat` |
| Bestenlisten | **keine**, und es bleibt dabei (DEC-025) |
| Competitive-Integrity | **keine Behauptung**. Ohne Server gibt es keine |

### Das eigentliche Problem war nicht das Melden, sondern das Doppelmelden

Eine lokale Partie endet, während dieses Gerät zusieht — genau einmal. Daran
kann `noteResult` hängen. Eine Onlinepartie hat diese Flanke nicht: Der
entscheidende Zug kann der des Gegners sein, gespielt während die App
geschlossen war. Das Gerät sieht also als Erstes eine Stellung, die bereits
vorbei ist — und sieht dieselbe Stellung danach bei jedem Refresh, bei jedem
Wechsel in den Vordergrund und bei jedem erneuten Öffnen wieder.

| Frage | Ergebnis |
|---|---|
| „Ist sie gerade zu Ende gegangen?" | meldet **gar nichts** |
| „Ist sie zu Ende?" | meldet bei **jedem** dieser Ereignisse |
| „Ist sie zu Ende und schon abgerechnet?" | meldet **genau einmal** |

Die dritte Frage wird gestellt. `AchievementLedger` beantwortet sie und liegt
auf der Platte, damit auch ein Fortsetzen am nächsten Tag abgedeckt ist.

Game Center ignoriert eine Wiederholung ebenfalls — `GKAchievement` behält das
erste Abschlussdatum. Der Ledger ist also die zweite von zwei Absicherungen und
nicht eine Wette auf Apples Verhalten.

### Nachweis

16 Tests in zwei Suites. **Beide Negativkontrollen wurden gefahren, nicht
angenommen:**

| Kontrolle | Erwartung | Ergebnis |
|---|---|---|
| Ledger abgeschaltet | nur die beiden Doppelmelde-Tests fallen | genau diese beiden, sonst keiner |
| Meldung ganz abgeschaltet | alle positiven Tests fallen | alle gefallen |

Geprüft wird unter anderem: jeder der vier Sitze bekommt genau seine eigene
Menge; nur ein tatsächlich gewinnender Sitz bekommt „Gewonnen"; eine beim
Öffnen bereits beendete Partie meldet trotzdem; zehnmaliges `adopt` meldet
einmal; ein neuer Prozess über demselben Ledger meldet nicht erneut; eine
**andere** Partie wird sehr wohl noch gemeldet.

### Was auf Hardware noch offen ist

Die Tests beweisen die Logik, nicht die Zustellung an Apple. Schritte 27–32 der
`GAME_CENTER_E2E_CHECKLIST.md` prüfen das echte Verhalten, und 30–32 sind die
wichtigen: Doppelvergabe ist der wahrscheinlichste Fehlermodus und sie ist
unsichtbar, solange niemand eine beendete Partie absichtlich erneut öffnet.

```
ENTSCHEIDUNG:  ☑ B — Reporting ergänzt, Build 43, erneute QA
```
