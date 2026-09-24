# Store screenshots — human review and sign-off

**Current status: ASC UPLOADED. Not HUMAN REVIEWED.**

Forty-five images are at Apple, attached to version 1.0.0, and every technical
check passes: right dimensions, right order, delivery state COMPLETE per set,
read back from App Store Connect rather than assumed from an upload.

**None of that is an approval.** Automatic verification answers "is this a
well-formed image in the right slot". It cannot answer "is this worth showing
to somebody deciding whether to buy the app", and it has already been wrong
about that in the most embarrassing way available: an image that passed every
check showed a Game Center authentication failure — a warning triangle and a
"Try again" button — and it was uploaded.

The status becomes **HUMAN REVIEWED** when the owner has looked at every image
and signed the block at the end of this file. Not before, and not because a
script said the set was fine.

---

## What to review with

Open **`SCREENSHOT_REVIEW.html`** (19.7 MB, images embedded — it opens from
anywhere, no folder needed). Each series starts with a contact sheet so the
sequence can be judged as a sequence, then every image appears large with its
checks unticked.

The files themselves are in `artifacts/store-screenshots/<series>/`.

---

## Reject on sight

Any **one** of these means the image does not ship. They are not weighed
against the rest of the sheet, and a good image with one of them is still out.

| | |
|---|---|
| 1 | An error dialog, an alert or a failure message |
| 2 | A retry, a loading state or a disabled control |
| 3 | An empty online area, or an online screen that is not signed in |
| 4 | A test artefact, debug interface, or anything a player cannot reach |
| 5 | A raw localization key |
| 6 | Text truncated, clipped or running off the edge |
| 7 | A washed-out, dim or half-drawn scene |
| 8 | Anything at all that could read as a defect |

---

## The set as it stands

45 images, not 60: the online-menu captures were removed before upload under
criterion 3, and have stayed out.

| Series | Locale | Display type | Images |
|---|---|---|---|
| `iphone-de` | de-DE | `APP_IPHONE_67` | 7 |
| `iphone-nl` | nl-NL | `APP_IPHONE_67` | 7 |
| `iphone-en` | en-US | `APP_IPHONE_67` | 7 |
| `ipad-de` | de-DE | `APP_IPAD_PRO_3GEN_129` | 8 |
| `ipad-nl` | nl-NL | `APP_IPAD_PRO_3GEN_129` | 8 |
| `ipad-en` | en-US | `APP_IPAD_PRO_3GEN_129` | 8 |

### Why there is no online screenshot

There is no happy-path online image, and there will not be one from this Mac.
In a simulator the online screen can only ever show a Game Center
authentication failure — there is no account to sign in with — so every capture
of it is an instance of criterion 3. A usable online screenshot has to be taken
on a real device, signed in, in a real match.

That is a deliberate gap, not an oversight: **shipping no online screenshot is
better than shipping a broken one.** If one is wanted for 1.0.0, it comes out of
the hardware session.

---

## Per-image verdict

One row per image. `APPROVE`, `REPLACE` or `REORDER` — an empty cell is not an
approval.

### iPhone — Deutsch (de-DE)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-phone-four-players-portrait.png` | | |
| 2 | `02-phone-menu-portrait.png` | | |
| 3 | `03-two-players-portrait.png` | | |
| 4 | `04-phone-six-players-portrait.png` | | |
| 5 | `05-phone-mid-match-portrait.png` | | |
| 6 | `06-phone-seven-split-portrait.png` | | |
| 7 | `07-phone-jack-swap-portrait.png` | | |

### iPhone — Nederlands (nl-NL)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-phone-four-players-portrait.png` | | |
| 2 | `02-phone-menu-portrait.png` | | |
| 3 | `03-two-players-portrait.png` | | |
| 4 | `04-phone-six-players-portrait.png` | | |
| 5 | `05-phone-mid-match-portrait.png` | | |
| 6 | `06-phone-seven-split-portrait.png` | | |
| 7 | `07-phone-jack-swap-portrait.png` | | |

### iPhone — English (en-US)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-phone-four-players-portrait.png` | | |
| 2 | `02-phone-menu-portrait.png` | | |
| 3 | `03-two-players-portrait.png` | | |
| 4 | `04-phone-six-players-portrait.png` | | |
| 5 | `05-phone-mid-match-portrait.png` | | |
| 6 | `06-phone-seven-split-portrait.png` | | |
| 7 | `07-phone-jack-swap-portrait.png` | | |

### iPad — Deutsch (de-DE)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-four-players-landscape.png` | | |
| 2 | `02-six-players-landscape.png` | | |
| 3 | `03-menu.png` | | |
| 4 | `04-two-players-landscape.png` | | |
| 5 | `05-seven-mid-split.png` | | |
| 6 | `06-jack-swap-targets.png` | | |
| 7 | `07-five-players-landscape.png` | | |
| 8 | `08-rulebook-landscape.png` | | |

### iPad — Nederlands (nl-NL)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-four-players-landscape.png` | | |
| 2 | `02-six-players-landscape.png` | | |
| 3 | `03-menu.png` | | |
| 4 | `04-two-players-landscape.png` | | |
| 5 | `05-seven-mid-split.png` | | |
| 6 | `06-jack-swap-targets.png` | | |
| 7 | `07-five-players-landscape.png` | | |
| 8 | `08-rulebook-landscape.png` | | |

### iPad — English (en-US)

| # | File | Verdict | Note |
|---|---|---|---|
| 1 | `01-four-players-landscape.png` | | |
| 2 | `02-six-players-landscape.png` | | |
| 3 | `03-menu.png` | | |
| 4 | `04-two-players-landscape.png` | | |
| 5 | `05-seven-mid-split.png` | | |
| 6 | `06-jack-swap-targets.png` | | |
| 7 | `07-five-players-landscape.png` | | |
| 8 | `08-rulebook-landscape.png` | | |

---

## Also worth a look, and separate

These are not per-image questions, so they do not belong in the table.

| | |
|---|---|
| Does each series read as a **sequence** — a reason to keep scrolling? | ☐ |
| Is the **first** image of each series the right one to lead with? | ☐ |
| Do the three languages tell the **same** story, in the same order? | ☐ |
| Is anything promised by an image that 1.0.0 does not do? | ☐ |
| Is anything 1.0.0 does well **missing** from the set? | ☐ |

---

## Sign-off

```
Build the images were taken from:
Reviewed on:
Reviewed by:

Images approved:          /45
Images to replace:
Images to reorder:

SCREENSHOTS:  ☐ HUMAN REVIEWED       ☐ CHANGES NEEDED

If changes are needed, what and why:
```

Until this block is filled in and signed, every document in this repository
says **ASC UPLOADED, not HUMAN REVIEWED**, and it stays that way.
