# App Store metadata

Laid out the way `deliver` expects, one directory per locale, so the text that
reaches App Store Connect is reviewed in this repository rather than typed into
a web form and forgotten.

## What may be written here

Only what the app does. Keezly 1.0.0 is a local game: two to six players on one
device, in teams or free-for-all, against three computer strengths or passed
around a table. There is **no online multiplayer**, no account, no server, no
advertising and no tracking.

Three claims are therefore forbidden, and each has a reason:

- **Nothing about anti-cheat.** There is no server to authorise a move, so
  there is nothing that could stop a modified client. Saying otherwise would be
  a security claim the software cannot keep (DEC-025).
- **Nothing about Game Center, leaderboards or online results.** The
  achievements are worked out locally and reported nowhere yet, and online
  results cannot be ranked honestly while a modified client can read every hand.
- **Nothing about features that are not in the build.** A screenshot or a
  sentence describing something the reviewer cannot find is a rejection.

## What is deliberately missing

`support_url`, `marketing_url` and `privacy_url` are **not** in this directory.
They are real addresses that must exist and be reachable, and guessing one is
worse than leaving it blank — a dead support link is a rejection and a wrong
privacy link is a legal problem. They are tracked as an external blocker
(MAN-13 in CURRENT_STATE.md) and must be filled in by the person who owns the domain.

## Limits App Store Connect enforces

| Field | Limit |
|---|---|
| `name` | 30 characters |
| `subtitle` | 30 |
| `promotional_text` | 170 |
| `keywords` | 100, comma-separated, no spaces after commas |
| `description` | 4000 |
| `release_notes` | 4000 |

`scripts/metadata-check.sh` measures every file against this table, because a
field one character over is refused at upload and the message does not say
which one.
