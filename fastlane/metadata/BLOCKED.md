# Fields that are deliberately not written here

Each of these is a real-world fact about a person or a domain, not a decision
about the app, and guessing one is worse than leaving it empty. They are
external blockers (MAN-13), and `scripts/metadata-check.sh` fails while any of
them is missing — so the set cannot be uploaded half-finished by accident.

| File | Why it is not here |
|---|---|
| `copyright.txt` | The legal rights holder's name, exactly as it should appear. A name inferred from a git account or a home directory is a guess in a legal field |
| `<locale>/support_url.txt` | Must be a page that exists and answers people. A dead support link is a rejection |
| `<locale>/privacy_url.txt` | Must be a reachable privacy policy. A wrong one is a legal problem, not a cosmetic one |
| `<locale>/marketing_url.txt` | Optional, and omitted rather than invented |
| App Privacy answers in App Store Connect | Keezly collects nothing, which is an answer somebody has to give in the web form under their own name. The facts are in `PRIVACY.md`; the declaration is theirs to make |

Everything else in this directory is written, translated and checked.
