# Keezly 1.0.0 — Release Candidate

**Stand 2026-09-23.** Der Kandidat ist **Build 42**. Build 41 ist von der
Geräte-QA **abgelehnt** worden und darf nicht mehr eingereicht werden.

| | |
|---|---|
| Version | **1.0.0** |
| Build | **42** |
| Git HEAD | `20f6225dd308555753b8ab7cd40844f8b27337f6` |
| SHA-256 (IPA) | `984c06f9da5d79875d4b2d5d2939e1b4906fbde091fe7cbbfae1337aa5e58baa` |
| Archive-Quelle | lokal, `xcodebuild archive`, Release, `generic/platform=iOS` |
| Export-Quelle | lokal, `app-store-connect`, `signingStyle=automatic`, `testFlightInternalTestingOnly=false` |
| Signatur | `Apple Distribution: RENÉ SUESS (KZFCCDV6A8)`, flags `0x0` |
| Profil | `iOS Team Store Provisioning Profile: de.gcng.keezly` |
| Apple-Validierung | `altool --validate-app` → `VERIFY SUCCEEDED with no errors` |
| Upload | `altool --upload-app`, Delivery UUID `890a4995-5801-4df3-9a25-c1b124553966` |

## Artefakt-Audit vor dem Upload

| | |
|---|---|
| Bundle ID | `de.gcng.keezly` |
| Version / Build | 1.0.0 (42) |
| Plattform | iPhoneOS, Device Family 1+2 |
| `codesign --verify --deep --strict` | erfüllt die Designated Requirement |
| Zertifikat CN / Requirement CN | **NFC / NFC — identisch** |
| `get-task-allow` | `false` |
| `beta-reports-active` | `true` |
| Game-Center-Entitlement | vorhanden |
| PrivacyInfo | vorhanden |
| Lokalisierungen | `de.lproj`, `nl.lproj`, `en.lproj` |
| AppIcons / Sounds | 2 / 7 |
| Debug-Artefakte | 0 |

## Von Apple zurückgelesen

```
version              42
processingState      VALID
expired              false
uploadedDate         2026-09-23T13:09:33-07:00
minOsVersion         17.0
usesNonExemptEncryption  false
preReleaseVersion    1.0.0 (IOS)
internalBuildState   IN_BETA_TESTING
externalBuildState   READY_FOR_BETA_SUBMISSION     ← nicht Internal Only
Version 1.0.0     -> Build 42
```

## Warum Build 41 ersetzt wurde

Die Geräte-QA meldete zwei P0-Befunde. Einer davon war reproduzierbar und ist
behoben, der andere ist es bis heute nicht.

| Befund | Ergebnis |
|---|---|
| Absturz beim Online-Spiel (ISS-021) | **behoben** in `c4a8278`, Regressionstest vorhanden |
| Gemeldete Rückwärtsbewegung (ISS-022) | **nicht reproduzierbar**, Core durch sieben semantische Richtungstests widerlegt |

ISS-021: `OnlineMenuView` entschied mit `seats % 2 == 0` selbst darüber, ob
Teams angeboten werden, statt `TableConfiguration.allowsTeams` zu fragen. Bei
einer ungeraden Sitzzahl blieb ein zuvor gesetztes `teams = true` stehen und
`GameConfiguration` bekam eine Kombination, die es nicht gibt. Der Absturz
passierte, **bevor** überhaupt eine GameKit-Methode gerufen wurde — Game Center
war nie beteiligt. Behoben wurde die doppelte Regel, nicht das Symptom.

Details und die vollständige Beweisführung zu ISS-022: `KNOWN_ISSUES.md`.

## Der Signing-Befund, der zur lokalen Distribution geführt hat

Ein A/B-Test mit identischem Quellstand, identischem Team und identischen
Entitlements. Der einzige Unterschied war, wer signiert:

| | Cloud Build 40 | Lokal Build 41 / 42 |
|---|---|---|
| Zertifikat | Cloud Managed Apple Distribution | Apple Distribution (lokal) |
| Zertifikat CN | NFC (`…52 45 4E c389 20…`) | NFC (`…52 45 4E c389 20…`) |
| Requirement CN | **NFD (`…52 45 4E 45 cc81 20…`)** | NFC |
| `codesign --verify --strict` | **does not satisfy its Designated Requirement** | satisfies its Designated Requirement |
| Apple `altool --validate-app` | **90035 Invalid Signature** | **VERIFY SUCCEEDED with no errors** |

Apples Cloud-Managed-Zertifikat schreibt den Zertifikatsnamen in die Designated
Requirement in NFD, während das Zertifikat selbst NFC trägt — gleiche
Buchstaben, andere Bytes, und die Prüfung scheitert an genau dieser Klausel.
Getestet wurde jede Klausel einzeln; `anchor apple generic`, `identifier`,
`subject.OU` und das Marker-Feld bestehen alle, nur `subject.CN` nicht.

Das ist ein Fehler auf Apples Seite bei Namen mit Nicht-ASCII-Zeichen. Er ist
**nicht** Teil dieses Projekts und wird vor 1.0 nicht weiter repariert.

## Statusbegriffe, streng getrennt

| | |
|---|---|
| CLOUD BUILD / TEST / ANALYZE | **VERIFIED** |
| CLOUD ARCHIVE | **technisch erzeugt** — kein gültiges Distributionsartefakt |
| CLOUD DISTRIBUTION ARTIFACT | **INVALID SIGNATURE / 90035** |
| XCODE CLOUD ASC UPLOAD | **BLOCKED** — Session Proxy Provider |
| LOCAL DISTRIBUTION BUILD | **VERIFIED** |
| APPLE VALIDATION | **VERIFIED** |
| NEW TESTFLIGHT BUILD (42) | **VERIFIED** |
| GERÄTE-QA an Build 42 | **AUSSTEHEND** |
| GAME CENTER ONLINE E2E | **AUSSTEHEND** — braucht zwei echte Geräte |

Build 42 ist damit **technisch** verifiziert und auf TestFlight verfügbar. Er
ist **nicht** von einem Menschen auf Hardware gespielt worden. Die beiden
Aussagen werden nicht vermischt.

### Korrektur einer früheren Aussage

Am selben Tag wurde hier „CLOUD ARCHIVE = VERIFIED" und „DISTRIBUTION SIGNING =
VERIFIED" festgehalten. **Das war falsch.** Geprüft worden waren damals nur die
Authority-Zeile und die Entitlements des Cloud-Artefakts — nie eine strenge
Signaturprüfung und nie Apples eigener Validator. Beide hätten es sofort
verworfen. Der Fehler war methodisch: eine plausible Teilprüfung wurde als
Beweis genommen.

### Korrektur einer zweiten Aussage

Build 41 war hier als „eingefroren, keine Codeänderung ohne konkreten Defekt"
festgehalten. Die Geräte-QA hat einen konkreten Defekt gefunden. Der Eintrag
steht nur noch als Historie; **Build 41 ist abgelehnt**.
