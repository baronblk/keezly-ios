# Keezly — Release Checklist

A real gate, not decoration (§147). A box is ticked only with evidence: a test
run, a build number, a verified manual step. If something was not checked, it
stays unticked and is marked `NOT RUN` — never "probably fine" (§139).

---

## Release 1.0.0 — status: **NOT READY**

The app does not build yet. This checklist is established now so it is filled in
as work lands, not reconstructed at the end.

### Build and versioning

- [ ] `MARKETING_VERSION` is `1.0.0`
- [ ] Build number is monotonic and derived from CI
- [ ] Git tree clean, release commit tagged
- [ ] Release configuration contains no debug menu, AI debug output or board overlay
- [ ] No hidden opponent information reachable in a release build

### Tests

- [ ] Rules engine unit tests green — *currently: 57 passed at commit `64931ef`*
- [ ] AI simulation green — NOT RUN (no AI)
- [ ] UI tests green — NOT RUN (no app target)
- [ ] Large-scale randomised simulation green — partial: 221 matches in the invariant suite
- [ ] No known critical bugs — *currently true; see `KNOWN_ISSUES.md`*

### Simulator matrix

- [ ] iPhone, smallest supported form factor
- [ ] iPhone, current standard
- [ ] iPhone, large
- [ ] iPad mini
- [ ] iPad 11"
- [ ] iPad 13"
- [ ] Portrait and landscape where applicable

### Physical device gates (§170)

These are mandatory. A release candidate may **not** ship with them `BLOCKED`
(§178). Current status: **BLOCKED — no physical device is paired with this Mac**
(MAN-09, MAN-10).

**Physical iPhone**

- [ ] Install · [ ] Launch · [ ] New game · [ ] 2-player match · [ ] AI opponent
- [ ] Card interaction · [ ] Jack swap · [ ] Seven split · [ ] Capture · [ ] Home entry
- [ ] Rotation · [ ] Background and resume · [ ] Haptics · [ ] Audio · [ ] Game Center

**Physical iPad**

- [ ] Install · [ ] Launch · [ ] Landscape · [ ] Portrait · [ ] Large board layout
- [ ] 4-player match · [ ] 6-player match · [ ] Team match · [ ] AI opponent
- [ ] Cards legible at normal viewing distance · [ ] Touch interaction · [ ] Rotation
- [ ] Multitasking where supported · [ ] Background and resume · [ ] Game Center
- [ ] Performance — launch time, frame smoothness, memory, energy, thermals

**Long-run test (§172)**

- [ ] Several complete matches back to back, varying player counts, with AI,
      rotation, backgrounding and match restore — no state corruption, no
      runaway memory, no hang

### Gate summary (§178)

| Gate | Result |
|---|---|
| Simulator | NOT RUN |
| Physical iPhone | BLOCKED |
| Physical iPad | BLOCKED |
| Game Center real device | BLOCKED |

### Gameplay completeness

- [ ] 2, 3, 4, 5 and 6 players all playable
- [ ] Team play (2×2 and 3×2) and free-for-all
- [ ] Pass & play with the privacy hand-off
- [ ] Mixed human/AI tables
- [ ] Easy, Medium and Hard AI, none of them cheating
- [ ] Autosave and resume after a crash
- [ ] Replay of finished local matches

### Game Center

- [ ] Authentication, including graceful failure
- [ ] Turn-based match: create, invite, automatch, resume, rematch, resign
- [ ] Online restore after app restart
- [ ] Duplicate and stale turn submissions are ignored, never applied twice
- [ ] Achievements configured and firing
- [ ] Leaderboards configured and reporting
- [ ] Verified in a real match between two Apple IDs

### Accessibility

- [ ] VoiceOver: a full match is playable
- [ ] Dynamic Type across all screens
- [ ] Reduce Motion honoured
- [ ] Reduce Transparency honoured
- [ ] Contrast sufficient; no information carried by colour alone
- [ ] Full Keyboard Access on iPad
- [ ] Alternative list of legal actions available

### Localisation

- [ ] Dutch (nl-NL) complete and reviewed
- [ ] German (de-DE) complete and reviewed
- [ ] English (en) complete and reviewed
- [ ] No hardcoded visible strings
- [ ] No clipped text in any language on any tested device

### Brand and assets

- [ ] App icon final; 1024px master, dark and tinted variants
- [ ] Icon legible at 29, 40, 60, 120, 180 px
- [ ] Editable icon sources committed under `Brand/`
- [ ] All artwork, sounds and rule texts are original

### Store

- [ ] Screenshots complete for de-DE, nl-NL, en — iPhone and iPad
- [ ] iPad 13" landscape screenshots lead the iPad set
- [ ] Screenshot quality gate passed (no debug overlay, no keyboard, no loading
      spinner, no placeholder names, no personal data)
- [ ] Metadata complete per locale: subtitle, promotional text, description,
      keywords, what's new, support and privacy text
- [ ] Privacy manifest present if required
- [ ] App Store privacy answers prepared

### Pipeline

- [ ] `bundle exec fastlane release_check` green
- [ ] Xcode Cloud "Keezly Release" workflow green
- [ ] TestFlight build installed and smoke-tested
- [ ] No secrets anywhere in the repository (secret scan passed)

---

## Sign-off

A release is approved only when every box above is ticked with evidence and
`CURRENT_STATE.md` records the verified commit.
