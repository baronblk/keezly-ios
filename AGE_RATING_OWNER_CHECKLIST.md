# Age Rating — for the owner to confirm

**Not submitted on the owner's behalf.** An age rating is a declaration in his
name. This sets out what App Store Connect currently holds, what the app
actually contains, and where the two disagree.

Read back from Apple on **2026-09-23**.

---

## One answer disagrees with the app

| Apple's question | Currently in ASC | What Keezly contains | Proposed |
|---|---|---|---|
| **Contests** | `INFREQUENT_OR_MILD` | **Nothing.** No prize, no entry, no draw, no sweepstake, no external competition | **NONE** |

Apple's "Contests" question is about contests, sweepstakes and prize draws run
**through the app**. A competitive board game is not one: two people playing
Keezen are competing with each other, not entering anything. There is no prize
of any kind, and no code anywhere that awards one.

Searched for and not found: any purchase flow, any prize logic, any external
entry, any sweepstake. The app has no in-app purchases at all.

**This is the one field to change.** Everything else already matches.

---

## Everything else already matches the app

All `NONE` or `false` in App Store Connect, and correct:

| Question | Value | Why it is right |
|---|---|---|
| Cartoon or Fantasy Violence | NONE | Pieces are sent back to their start. Nothing is depicted as harm |
| Realistic Violence | NONE | — |
| Prolonged Graphic or Sadistic Violence | NONE | — |
| Sexual Content or Nudity | NONE | — |
| Graphic Sexual Content and Nudity | NONE | — |
| Profanity or Crude Humour | NONE | The whole text of the app is in `Localizable.xcstrings` and is plain |
| Alcohol, Tobacco or Drug Use | NONE | — |
| Mature or Suggestive Themes | NONE | — |
| Horror or Fear Themes | NONE | — |
| Medical or Treatment Information | NONE | — |
| Gambling | false | No wagering, no simulated gambling, no chance-for-prize |
| Simulated Gambling | NONE | Cards are used to move pieces on a board. Nothing is staked |
| Loot Box | false | No purchases and no randomised rewards |
| Unrestricted Web Access | false | No web view of any kind |
| User Generated Content | false | Nothing a player types or uploads — there is nothing to type |
| Messaging and Chat | false | **Checked again after online play was added.** Keezly sends the position of the match and nothing else. There is no chat, no free text, no way to send a word to another player |
| Social Media | false | No sharing, no feeds |
| Advertising | false | None |
| Parental Controls | false | None needed |
| Age Assurance | false | None |
| Health or Wellness Topics | false | — |

`kidsAgeBand` is null and `isOrEverWasMadeForKids` is false. Keezly is a family
board game and children will play it, but it is not submitted to the Kids
Category, which brings requirements the app does not meet and does not need.

---

## Game Center, and why it changes nothing here

Online play added one thing: two people can take turns in the same match. It
did **not** add chat, names typed by players, user content, or any way for one
player to send another anything but a legal move. Apple's own Game Center
identity and friend interfaces are Apple's, shown by Apple, and governed by
Apple's own rating.

---

## What the owner needs to do

1. App Store Connect → Keezly → Age Rating → Edit.
2. Change **Contests** from *Infrequent/Mild* to **None**.
3. Leave every other answer as it is.
4. Confirm the resulting rating.

One field. Nothing else needs touching, and nothing here is submitted
automatically.
