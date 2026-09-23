# Achievements in Onlinepartien — Befund und offene Entscheidung

**Anlass:** die Annahme „Onlinepartien bringen nie Erfolge" wurde hinterfragt.
Sie hält der Prüfung nicht stand, und das ist hier belegt statt behauptet.

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

## Entscheidung liegt beim Owner

Build 41 ist eingefroren; ohne konkreten Defekt wird nicht neu gebaut. Ob dies
ein Defekt ist, ist eine Produktentscheidung:

**A — als bewusste 1.0-Grenze dokumentieren.**
Erfolge werden nur in lokalen Partien gegen den Computer vergeben. Nichts im
Store-Text und nichts auf der Website verspricht etwas anderes; beide nennen
„zehn Erfolge", ohne den Modus zu nennen. Kein neuer Build.

**B — als Defekt behandeln.**
Ein Online-Spieler kann die zehn beworbenen Erfolge nicht erreichen, obwohl die
Zuordnung eindeutig ist. Dann: Reporting ergänzen, neuer Build, erneute QA.

**Unabhängig von A oder B zu korrigieren:** die TestFlight-Notiz und der
Code-Kommentar behaupten eine Begründung, die für Online nicht zutrifft.

```
ENTSCHEIDUNG:  ☐ A — dokumentierte 1.0-Grenze   ☐ B — Defekt, neuer Build
```
