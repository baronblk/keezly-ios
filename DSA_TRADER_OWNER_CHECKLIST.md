# DSA trader status — for the owner to confirm

**Not answered on the owner's behalf.** Under the EU Digital Services Act,
Apple requires every developer distributing in the European Union to declare
whether they act as a **trader**. That is a legal status, not a technical fact,
and nothing in this repository can establish it.

---

## What App Store Connect currently holds

Read on **2026-09-23**: the App Store Connect API exposes no DSA trader field
on the app or the version resources it serves to this key. The declaration is
made at **account level**, in App Store Connect under *Business* → *Trader
Status*, and it applies to the developer account rather than to Keezly alone.

**So this cannot be read back by API, and its state must be checked by the
owner in the web interface.** If it has already been answered for the account,
it already covers Keezly and there is nothing further to do.

---

## What is known, and is relevant

Facts from this project, offered as input to a decision that remains the
owner's:

| | |
|---|---|
| Seller | Rene Süß, Barbarossastraße 91, 09112 Chemnitz, Germany |
| Status stated on the website | Kleinunternehmer under § 19 UStG — no VAT identification number under § 27a UStG |
| Keezly's price | €2.99, paid, base territory Germany |
| Distribution | Intended for EU territories |

Selling a paid app to consumers in the EU, in the course of a business, is
ordinarily what "trader" means — but the term is defined by law, it turns on
facts about the person rather than the software, and a Kleinunternehmer is
still capable of being a trader. **This is exactly the kind of question that
must not be answered by inference from a repository.**

---

## Why this matters for the release

Apple does not allow an app to be distributed in the EU while the trader
declaration is outstanding, and for a trader the verified contact details are
shown publicly on the App Store listing. Getting it wrong in either direction
has consequences the code cannot undo.

---

## The single owner action

1. App Store Connect → **Business** → **Trader Status**.
2. Check whether the account declaration is already complete.
3. If it is not, answer it — taking advice if there is any doubt, because this
   is a legal status and not a setting.
4. If a trader, complete the verification Apple asks for; the contact details
   will appear on the public listing.

**Owner decision required: ☐ already declared for the account  ☐ answered now**

Nothing in this file is legal advice.
