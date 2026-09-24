# Keezly — Website

**Status: GENERATED / DEPLOYABLE. NOT LIVE.**

Measured, not assumed — `scripts/website-live-check.py` on **2026-09-24**:

```
checking 15 pages under https://gcng.de/KEEZLY/
all 15 -> HTTP 404
WEBSITE LIVE CHECK: FAILED — 15 fault(s)
The site is NOT LIVE VERIFIED.
```

Nothing anywhere in this repository claims the site is live, and nothing will
until that command exits 0.

| | |
|---|---|
| Source | `website/` — `build.py`, `content.py`, `prose.py`, `src/assets/` |
| Output | `website/dist/` (54 files, ~1.1 MB) |
| Artifact | `website/website-keezly-1.0.0.zip` (904 KB) |
| Target | `https://gcng.de/KEEZLY/` |
| Build | `python3 website/build.py` |
| Check (files) | `python3 scripts/website-check.py website/dist` |
| Check (published) | `python3 scripts/website-live-check.py` |
| Deploy | `website/DEPLOY.md` |

15 pages: home, support, accessibility, privacy and imprint, in German, Dutch
and English.

---

## After the owner uploads it

One command, and it decides:

```bash
python3 scripts/website-live-check.py
```

It fetches every one of the 15 pages over HTTPS at the real address and checks,
per page: served with HTTP 200, served as HTML, `lang` matching the section it
is in (`de`, `en`, `nl`), the word Keezly actually present — which catches a
host that answers a missing page with a 200 — and none of `DRAFT`, `ENTWURF`,
`LEGAL REVIEW REQUIRED`, `OWNER ACTION`, `TODO`, `FIXME`, `PLACEHOLDER` or
`Lorem ipsum`. It then follows every off-site link the pages declare, including
the two to `support.gcng.de`, and fails on any that does not answer.

That covers what was asked for: all DE/NL/EN pages, and specifically privacy,
imprint and support in each of the three.

**App Store URLs.** There are none on the site today, and that is correct — the
app is not released, so a link to its product page would lead nowhere. The
check says so rather than passing silently. Once 1.0.0 is on the store and the
links are added, the same command verifies each one resolves and names either
`de.gcng.keezly` or `6814932630`, so a link cannot quietly point at somebody
else's app.

The status line at the top of this file is updated from that command's output
and from nothing else.

---

## Why this is internal and the site is not

The public pages carry no notes, no drafts and no developer commentary. They
did for a while — "draft, human legal review required" — which was right while
the provider's particulars were unconfirmed and wrong to publish. A visitor
reading an imprint does not want to know about the project's internal state,
and a privacy page that calls itself a draft is worse than useless.

`scripts/website-check.py` now fails the build if `DRAFT`, `ENTWURF`, `LEGAL
REVIEW REQUIRED`, `OWNER ACTION`, `TODO`, `FIXME` or `PLACEHOLDER` reaches a
published page. Everything of that kind belongs here instead.

---

## Legal content

The provider's particulars in `website/content.py` → `IMPRESSUM` were
**supplied and confirmed by the owner on 2026-09-22**. They are not inferred
from any other source and must not be edited without him.

```
Rene Süß
Barbarossastraße 91
09112 Chemnitz
Deutschland
support@gcng.de · 0151 55386821
Kleinunternehmer gemäß § 19 UStG — keine USt-IdNr. nach § 27a UStG
```

The imprint is written to § 5 DDG and carries the consumer-arbitration
declaration. All three languages state identical facts; only the surrounding
wording is translated, and the German legal references are named as German ones
in the Dutch and English versions rather than being mapped onto local statutes
that do not apply.

Earlier revisions of this file used `Rene Suess` and an older telephone number,
taken from the public support site. Both are superseded. The store copyright
string is `© 2026 Rene Süß`.

### What the privacy page may say

Derived from the code, not assumed:

- `Preferences` and `Welcome` write three keys to `UserDefaults`.
- `MatchStore` writes saved matches into Application Support.
- `GameCenterTransport` is the only file in the project that touches a network.
- A saved match holds a seed, the accepted actions, the table settings, a
  `UUID` match id and two timestamps. No name, and nothing derived from the
  hardware.

The hosting statement — a self-operated server inside the European Union — is
the owner's own, from the central privacy statement at `support.gcng.de`, which
the Keezly page links to for server-log specifics rather than restating them.

---

## The subpath is the whole risk

The site is served from `/KEEZLY/` and nothing in it assumes that. Every
internal link and asset reference is relative to the page emitting it. Three
things are absolute because the standards require it — `rel="canonical"`, the
`hreflang` alternates and the OpenGraph image — and all three come from
`CANONICAL_ROOT` in `content.py`. **If the site moves, change that one line.**

Paths are consistently upper-case `/KEEZLY/`:

| | German | Dutch | English |
|---|---|---|---|
| Home | `/KEEZLY/` | `/KEEZLY/nl/` | `/KEEZLY/en/` |
| Support | `/KEEZLY/support/` | `/KEEZLY/nl/support/` | `/KEEZLY/en/support/` |
| Privacy | `/KEEZLY/datenschutz/` | `/KEEZLY/nl/privacy/` | `/KEEZLY/en/privacy/` |
| Imprint | `/KEEZLY/impressum/` | `/KEEZLY/nl/colofon/` | `/KEEZLY/en/imprint/` |
| Accessibility | `/KEEZLY/barrierefreiheit/` | `/KEEZLY/nl/toegankelijkheid/` | `/KEEZLY/en/accessibility/` |

---

## What the checker does and does not cover

Covered: relative links only, every reference resolves, every image has alt
text, no JavaScript, no off-site assets, no claim the software cannot keep
(DEC-025), no internal markers, all three locales present with the same page
set, `robots.txt` and `sitemap.xml` present.

The leaderboard check distinguishes a claim from a denial by looking for a
negation shortly before the term — the privacy pages state that Keezly has
none, and a check that could not tell the difference would push somebody to
delete the sentence that makes the position clear. That is a heuristic and is
documented as one in the script.

**Not covered, and not implied:** whether the writing is any good, whether the
Dutch reads naturally to a Dutch speaker, whether the design is worth looking
at. Those need a person.

---

## Store URLs

Prepared in App Store Connect and **not yet reachable**. They must not be
treated as verified until the site is up and the check in `DEPLOY.md` returns
200 for every path.

| | |
|---|---|
| Marketing | `https://gcng.de/KEEZLY/` · `…/nl/` · `…/en/` |
| Support | `https://gcng.de/KEEZLY/support/` · `…/nl/support/` · `…/en/support/` |
| Privacy | `https://gcng.de/KEEZLY/datenschutz/` · `…/nl/privacy/` · `…/en/privacy/` |
