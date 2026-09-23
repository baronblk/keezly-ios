# Keezly 1.0.0 — Release Candidate

**Eingefroren am 2026-09-23.** Keine neue Buildnummer und keine Codeänderung,
solange die Geräte-QA keinen konkreten Defekt findet.

| | |
|---|---|
| Version | **1.0.0** |
| Build | **41** |
| Git HEAD | `468ada83d995c50df91ffa2f642a1823ea3426ae` |
| SHA-256 (IPA) | `ef7a37fb132f6cc943e5a439f8d646b1d5d3b1b0a98f18237cd818955a38ea6f` |
| Archive-Quelle | lokal, `xcodebuild archive`, Release, `generic/platform=iOS` |
| Export-Quelle | lokal, `app-store-connect`, `signingStyle=automatic`, `testFlightInternalTestingOnly=false` |
| Signatur | `Apple Distribution: RENÉ SUESS (KZFCCDV6A8)`, flags `0x0` |
| Profil | `iOS Team Store Provisioning Profile: de.gcng.keezly` |
| Upload | `altool --upload-app`, Delivery UUID `ed306834-bd02-4bd8-9dd4-bc3cfc588cfe` |

## Von Apple zurückgelesen

```
processingState      VALID
expired              false
uploadedDate         2026-09-23T12:26:53-07:00
minOsVersion         17.0
internalBuildState   READY_FOR_BETA_TESTING
externalBuildState   READY_FOR_BETA_SUBMISSION     ← nicht Internal Only
Version 1.0.0     -> Build 41
```

## Der Signing-Befund, der zu diesem Build geführt hat

Ein A/B-Test mit identischem Quellstand, identischem Team und identischen
Entitlements. Der einzige Unterschied war, wer signiert:

| | Cloud Build 40 | Lokal Build 41 |
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
| TESTFLIGHT | **VERIFIED** |

### Korrektur einer früheren Aussage

Am selben Tag wurde hier „CLOUD ARCHIVE = VERIFIED" und „DISTRIBUTION SIGNING =
VERIFIED" festgehalten. **Das war falsch.** Geprüft worden waren damals nur die
Authority-Zeile und die Entitlements des Cloud-Artefakts — nie eine strenge
Signaturprüfung und nie Apples eigener Validator. Beide hätten es sofort
verworfen. Der Fehler war methodisch: eine plausible Teilprüfung wurde als
Beweis genommen.
