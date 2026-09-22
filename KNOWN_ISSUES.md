# Keezly — Known Issues

Register of reproducible technical problems (§137). Status values:
`OPEN`, `INVESTIGATING`, `FIXED`, `VERIFIED`. An issue only becomes `VERIFIED`
after a test has actually been run and passed.

Open work that is not a defect belongs in `ROADMAP.md`, not here (§141).

---

## Open

| # | Summary | Severity |
|---|---|---|
| ISS-019 | The physical device gate stops at a password prompt | Blocker (hardware gate, needs a person) |
| ISS-016 | A seat colour does not reach 3:1 against the board | Accepted — colour proven redundant (contrast) |
| ISS-015 | Online play hides nothing from a modified client | Accepted limitation (fairness) |
| ISS-014 | Neither physical device will start a UI test runner | Blocker (hardware gate) |
| ISS-010 | No hardware keyboard or pointer available to verify M4.7 end to end | Verification gap |
| ISS-011 | Commit `1d46410` carries a message that does not match its content | Cosmetic (history) |

---

## Open — in detail

### ISS-013 — A small board has no room for what is drawn in its middle

- **Status:** FIXED, VERIFIED
- **Severity:** Minor (visual)
- **Component:** App / Board
- **Description:** Three separate faults, all of them the same mistake — the
  middle being sized against something other than the middle.
  1. The home lanes are four squares long whatever the table size, so on a
     two-seat board — half the track of a four-seat one — they run almost to
     the centre, and the draw pile, the played card and the turn indicator are
     drawn across them.
  2. The middle was a fixed fraction **of the view**. That was the same thing
     as a fraction of the board only while the view was the playing squares.
     When the board's bounds grew to hold the panel, its shadow and the air
     around it, the board shrank inside its frame and the middle did not.
  3. Both labels in the middle are text, and text has a legibility floor.
     Below about eleven points they stop shrinking while everything around
     them carries on, so on a phone the turn pill ends up half again the size
     it was drawn to be, lying across the pieces.
- **Reproduction:** `-KEEZLY_SEATS 2` on an iPad for (1);
  `./scripts/board-review.sh` for (2) and (3) — the phone captures show it
  plainly.
- **Expected:** Whatever is in the middle sits in the middle, at a size that
  can be read, on every board Keezly draws.
- **Fix:** three, in order.
  - Two seats show the table's own cards **beside** the board — a wooden tray
    opposite the other player, holding the deck, the played card, the turn and
    the round (DEC-021). Shrinking them to fit a field of a single square pitch
    made them unreadable, which is the worse fault. The lanes themselves were
    also set side by side rather than nose to nose, which is what gives that
    board a middle at all.
  - `BoardLayout.centreWidthFraction(aspect:)` measures the quiet field against
    `contentBounds` — the thing a view actually scales to fit — and sizes the
    middle from that. One answer, in `BoardCentreView.fitted(in:boardSide:)`,
    so the playing screen and the replay screen cannot drift apart; the replay
    had a hard-coded `0.26`.
  - A board too small to draw the labels at their designed size keeps the piles
    and moves the labels to a line **beneath** it, where they are legible
    without covering anything. The rule is about legibility, not about device
    class: the same phone in landscape, or an iPad in a narrow Stage Manager
    window, gets the same answer for the same reason.
- **What did not change:** `BoardGraph`, the rules, and the board itself. Only
  the presentation adapts, and every decision is written as a rule about
  available space rather than as a special case for a seat count or a device.
- **Verified by:** `InnerFieldTests`, including that the board's measured
  proportions are the ones the design was decided on — so a change to the lanes
  or the track cannot silently invalidate any of this — and the full capture
  set from `scripts/board-review.sh` at 2, 4 and 6 seats on phone, portrait
  tablet and a landscape-shaped pane.
- **Related files:** `App/Keezly/Board/BoardCentreView.swift`,
  `App/Keezly/Board/BoardLayout.swift`, `App/Keezly/Play/GameScreen+Layout.swift`,
  `App/Keezly/Replay/ReplayScreen.swift`
- **Related tests:** `InnerFieldTests`

### ISS-019 — The physical device gate stops at a password prompt

- **Status:** OPEN — blocked on a person, not on code
- **Severity:** Blocker for the physical-device gate
- **Component:** fastlane / device lanes
- **Description:** `fastlane device_ipad` runs the app suite on the physical
  iPad successfully — **27 suites passed** — and then, about a minute after the
  last one, prints `Password:` and waits on standard input. Nothing supplies
  it, so the lane hangs until it is killed.
- **What it is not:** this is **not** ISS-014. ISS-014 is the UI test runner
  refusing to start on either device. Here the unit phase completed on real
  hardware and the stop is a credential prompt in the transition to the next
  phase — most likely a codesigning identity or a developer-tools
  authorisation that has not been unlocked for a non-interactive session.
- **Reproduction:** `bundle exec fastlane device_ipad` with the iPad paired,
  wired, tunnel connected and Developer Mode on. Observed 2026-09-22 at commit
  `7314714`.
- **Why it stays open rather than being worked around:** a password is the
  device owner's to type. It is not written down here, it is not going into an
  environment variable, and no lane in this repository will be changed to
  accept one. Automating past a credential prompt is the wrong fix even when it
  works (§107).
- **What to try, in order, when somebody is at the machine:** run the lane
  interactively once and see what the prompt actually belongs to; if it is the
  login keychain, unlock the signing identity for the session; if it is
  `DevToolsSecurity`, authorise developer mode for the user once. Then record
  which it was here, because "a password prompt" is not yet a diagnosis.
- **Impact:** the physical iPad gate cannot be reported as passed. It is not
  reported as passed — `fastlane release_check` prints it as a separate line
  and ends with "not releasable".
- **Related files:** `fastlane/Fastfile`, `scripts/devices.sh`
- **Related documents:** `docs/DEVICE_TESTING.md`

### ISS-017 — Hard's play depends on how busy the machine is

- **Status:** FIXED, VERIFIED
- **Severity:** Major (reproducibility)
- **Component:** KeezlyCore / AI
- **Description:** `HardAgent` stopped sampling at a wall-clock deadline
  (`ContinuousClock`, 50 ms under `AIBudget.simulation`), so how many worlds a
  decision explored depended on how loaded the machine was. The same seed
  therefore played a **different match** on a busy machine than on a quiet one.
- **How it was found:** the honest way, and not the way anybody would want. A
  new soak run crashed on an assertion in `GameReducer.advanceTurn` (ISS-018).
  Re-running the identical filter, with only a diagnostic added, passed — and
  the diagnostic never fired. A seeded engine does not do that.
- **Why it matters beyond the annoyance:** every simulation result in this
  repository is stated as "measured at N over M matches", and a failing seed is
  supposed to be handed back as a bug report. Neither is true of a run that
  cannot be repeated. It also contradicts DEC-003 in the one place the project
  most relies on it.
- **What it did *not* affect:** saved matches and replays, which are the seed
  plus the **accepted actions**. A replay reproduces what happened because it
  is told what happened; it never asks an agent to think again.
- **Fix:** `AIBudget.maximumDuration` is now optional, and
  `AIBudget.simulation` leaves it `nil` — the headless harness consults no
  clock at all. The search is bounded by its own sample counts instead, which
  are small and fixed: six candidates, eight sampled worlds each, eight plies.
  Interactive play keeps its clock, because there a person really is waiting
  and the accepted actions are what gets recorded either way.
- **Related tests:** `HardAgentTests.simulationBudgetIsReproducible` — the same
  seed and position, twenty times, must choose the same move. The timing tests
  no longer ask `.simulation` how long it took, because that is now the wrong
  question to ask of it.
- **Related files:** `Packages/KeezlyCore/Sources/KeezlyCore/AI/AIAgent.swift`,
  `Packages/KeezlyCore/Sources/KeezlyCore/AI/HardAgent.swift`

### ISS-018 — A legal end position was reported as a broken rule engine

- **Status:** FIXED, VERIFIED
- **Severity:** Minor (a false assertion, not a wrong game)
- **Component:** KeezlyCore / GameReducer
- **Description:** `GameReducer.advanceTurn` walks the table looking for a seat
  with a legal move, dealing the next round when it finds none, and ended a
  whole 5/4/4 cycle of that with `assertionFailure("No seat could act across
  three consecutive deal rounds")`. A soak run reached that position.
- **Why the assertion was wrong:** a seat that has brought all four pawns home
  can never move again, whatever it is dealt. In a team match one seat of each
  team can be finished while the match runs on, so two of four seats can be
  permanently moveless — and the two that are left are stuck for a round
  whenever neither draws a card that starts a pawn, which on the five cards a
  round opens with is likely rather than rare. This is the ordinary end of a
  match, not a broken rule engine.
- **What the shipping build always did:** the assertion is compiled out, the
  function returns with the turn where it was, the caller force-folds that
  seat, and folding comes back through the same path and deals again. Matches
  complete. The release build was right and the debug build was calling a legal
  position a bug — which is the wrong way round, because an assertion that
  fires on legal positions is one people learn to comment out.
- **Fix:** the assertion is gone and the reason giving up is safe is written
  where the assertion was. **The bound itself is unchanged at one cycle.** That
  is deliberate: the cards that unstick the table arrive at the same rate
  whether the rounds are dealt inside one call or across several, so a larger
  number changes only how many forced folds get recorded on the way — and it
  keeps this a fix to the assertion rather than a change to the turn order. A
  rule engine that really has stopped offering moves still does not hang: it
  runs out of `MatchSimulator.maximumActions` and is reported as
  `didNotFinish` with its seed, which is a fact somebody can act on rather than
  a crash in a debug build only.
- **Why the position exists at all, given that a finished player takes over
  their partner's pawns (§8, and it is implemented):** taking over does not
  help when the partner's remaining pawns are also unmovable — waiting for a
  card that starts a pawn, or in the home lane needing an exact count. At the
  end of a match that is an ordinary few rounds, not a broken table.
- **Verified by:** the core suite, 176 tests, green in 145s with the assertion
  removed — the same 148s it took with it, so nothing was being held up by the
  crash.
- **Related files:**
  `Packages/KeezlyCore/Sources/KeezlyCore/Engine/GameReducer.swift`
- **Related tests:** `SoakTests` — 630 matches across every strength, table
  size, team mode and rule variant, which is what reached the position in the
  first place

### ISS-016 — A seat colour does not reach 3:1 against the board

- **Status:** OPEN — accepted, and only after a structural review found colour
  to be redundant everywhere it carries meaning
- **Severity:** Accepted limitation (contrast)
- **Component:** Design system, board

#### The measurement

`ContrastTests`, in the light appearance, against the board's own wood:

| | Ratio |
|---|---|
| Amber pawn | **1.23:1** |
| Green pawn | 2.14:1 |
| Blue pawn | 2.41:1 |
| Red pawn | 2.50:1 |
| The dark outline every piece carries | 2.03:1 |

WCAG 1.4.11 asks 3:1 for the boundary of a graphical element that carries
meaning. Nothing in this palette reaches it, and nothing will without darkening
a board whose appearance is settled (DEC-018).

#### Why that is acceptable — checked rather than asserted

A hue below the bar only matters if the hue is carrying information on its own.
Every distinction the board makes was gone through one at a time, and the two
that turned out to depend on colour were **fixed**, not excused:

| Question | Answer |
|---|---|
| Is a piece's owner identifiable without colour? | **Yes.** Every seat has its own `PawnMark` — circle, triangle, square, diamond, hexagon, chevron — drawn in white on the piece. Unique by test |
| Is a **waiting area** identifiable without colour? | **Now yes.** It was a coloured tray and nothing else; an *empty* one belonged to nobody visibly. It now carries the seat's own mark, engraved |
| Is a **home lane** identifiable without colour? | **Now yes.** Same fix. The generic ornamental chevron that used to sit at the lane's inner end has been *replaced* by the seat's mark — one shape doing the same job and saying more |
| Is a **protected start square** identifiable without colour? | **Yes.** It carries a solid ring the other holes do not |
| Is a **legal target** identifiable without colour? | **Now yes.** It was a solid ring in green — the same shape as a start square's ring, in a different hue. It is now **dashed**, and drawn outside the start square's rings rather than between them |
| Are **selected / selectable / focused** distinguishable without colour? | **Yes.** A selected card is raised out of the hand; a selectable piece is ringed; a selected piece is ringed *and* scaled; keyboard focus is a black-and-white double ring. All are shape or position |
| Does it work in greyscale? | **Yes** — looked at, and measured |

#### How it is checked

- `GrayscaleTests` renders the board twice, desaturates both, and compares the
  patch that should have changed. A distinction that survives only in colour
  scores near zero. **It found one**: a legal target drawn on a start square
  measured 3/255 in greyscale, because the dashed ring landed between the start
  square's halo and its ring. Moving it outside them fixed it.
- `scripts/grayscale-review.sh` writes six real board states — four, six and
  two players, free-for-all, a Jack ready, a Seven ready — each in colour, in
  greyscale, and stacked for comparison.
- `ContrastTests.seatColoursAreNotInvisible` fails if any seat gets *weaker*
  than it is today, so the shortfall cannot quietly grow.

#### What would still fix it properly

A materially darker board, or a second "high contrast" material. Both are
design decisions rather than adjustments, and neither is in 1.0.0. The board
was **not** darkened globally to chase a number, because a local
contour-and-mark answer turned out to be enough — and is the better answer
anyway: a shape helps somebody using the app in bright sunlight too.

- **Related files:** `App/Keezly/DesignSystem/PlayerIdentity.swift`,
  `App/Keezly/Board/PawnView.swift`, `App/Keezly/Board/BoardSurface.swift`

---

### ISS-015 — Online play hides nothing from a modified client

- **Status:** OPEN — accepted limitation, recorded rather than fixed (DEC-025)
- **Severity:** Fairness. Not a defect in the code; a property of the design
- **Component:** Online play
- **Description:** Every Game Center participant receives the same match data,
  which carries the seed and the accepted moves. Replaying them reproduces the
  whole position, including every opponent's hand and the order of the undealt
  deck.
- **Reproduction:** `OnlineHiddenInformationTests`. From the payload alone,
  using the app's own `OnlineMatchEnvelope.load`, every hand is reconstructed
  exactly and the remaining deck is read in order. No privileged access, no
  side channel, no bug.
- **Why it is not simply fixed:** the replay-and-compare check that makes a
  remote move trustworthy works *because* the receiver can reproduce the whole
  game. Remove the seed and that check goes too. Determinism and hidden
  information are in direct conflict here.
- **What does hold:** Keezly does not leak hidden information through its own
  interface or its own agents. That is a real guarantee and it is tested — it
  is simply a different guarantee.
- **Options considered and not taken:** per-player encrypted hands (the dealing
  device still knows everything), a commit-and-reveal shuffle (several
  interactive rounds per deal, repeated every round of a 5/4/4 cycle, over a
  transport where players may be offline for days), and a server of our own
  (one complete answer — a correct multi-party protocol would be another — and
  a product decision in its own right). Set out in full in DEC-025.
- **Consequence:** online play in 1.0.0 is friendly play. Nothing may claim
  otherwise, and online results are not a sound basis for a competitive
  leaderboard — a constraint that lands on M9.

### ISS-014 — Neither physical device will start a UI test runner

- **Status:** OPEN — blocked on the devices, not on the code
- **Severity:** Blocker for the hardware gate only
- **Component:** Device test environment
- **Description:** Both hardware gates passed earlier the same session at commit
  `9a2d4e3` (80 passed, 3 skipped, on each device). Re-running them on the
  polish pass fails before any test executes:
  - iPhone 17 Pro — `Lost pending connection to the test runner before launch`,
    and `scripts/devices.sh` now reports it as
    `unknown / tunnel unavailable`: it has left the wired connection.
  - iPad (A16) — still `wired / tunnel connected` and reported usable, but
    `The test runner failed to initialize for UI testing (Timed out while
    enabling automation mode)`.
- **What is not the cause:** the build. Both gates build and install; the
  failure is in starting the runner. The same commit passes 83 tests on the
  simulator.
- **Possible contributor:** a hung iPhone run was terminated with `pkill` after
  31 minutes without progress, which can leave a device's automation mode in a
  stuck state.
- **Remedy (needs the devices in hand):** unlock both devices and leave them
  unlocked, reconnect the iPhone by cable, and restart either device if
  automation mode stays stuck. Then re-run `bundle exec fastlane device_gate`.
- **Recorded as BLOCKED, never as passed** (§177): the last genuine hardware
  result stands at `9a2d4e3` and the polish pass has **not** been verified on
  hardware.

### ISS-012 — Landscape captures carry a 25% black margin

- **Status:** FIXED, VERIFIED
- **Severity:** Minor (tooling; blocks App Store submission of captures)
- **Component:** Screenshot harness
- **Description:** `XCUIApplication.screenshot()` on a rotated app returns the
  application element's region rather than the window, and on this simulator
  that region is exactly three quarters of the screen's short side. Every
  landscape capture therefore carries a black band.
- **Reproduction:** Run `DesignReviewScreenshots` and measure the captures:
  **exactly 516 of 2064 rows** are black on every landscape capture and **none**
  on any portrait one. The number is identical every run.
- **Impact:** None on a design review — the interface itself is complete and
  correctly oriented. It does matter for App Store screenshots.
- **Attempted:** switching to `XCUIScreen.main.screenshot()` removed the band
  but returned portrait-shaped images, and a 1.5-second settle before capturing
  changed nothing. The cause is the capture API, not a rotation still in
  flight.
- **Settled cause, for the pipeline to build on:** measured on a rotated iPad,
  `app.screenshot()` returns 2064×2752 with a quarter of it black, while
  `XCUIScreen.main.screenshot()` returned the full 2752×2064. The screenshot
  pipeline is built on the **screen** capture.
- **That second measurement no longer holds, and the pipeline found out.**
  On the current toolchain `XCUIScreen.main.screenshot()` also comes back
  2064×2752 on a rotated iPad: the whole landscape screen, complete and not
  black anywhere, but stored in the unrotated framebuffer and so lying on its
  side. The app really is in landscape in it — the board is centred with the
  seat panels flanking it — and only the frame is the wrong way round. The
  quarter-turn in `attach` was kept as a guard rather than deleted when it
  stopped firing, which is the only reason this was a correction rather than a
  rediscovery.
- **And the defect underneath it, which is the real one: the orientation was
  in a tag rather than in the pixels.** `UIImage(data:
  screenshot.pngRepresentation)` reports its `size` as 2752×2064 — landscape,
  and correct — while the bytes behind it are 2064×2752 portrait plus an
  orientation tag. UIKit honours the tag, so `size`, the quarter-turn guard and
  every assertion in `attach` agreed the capture was landscape. Nothing else
  honours it: Pillow reads the exported file as portrait, and so would App
  Store Connect.

  The evidence was a single file of **2,550,479 bytes** that the test measured
  as 2752×2064 and the disk measured as 2064×2752 — the same bytes, read two
  ways, and only one of the two readers is the one that matters.

  `flattened` now redraws any image that is not already `.up`, which puts the
  orientation into the pixels. `attach` also measures the **encoded bytes**
  before attaching them, because that is the only measurement in that file
  which was ever going to catch this.
- **The lesson, which is worth more than the fix:** an assertion about a
  capture proves nothing about the capture that ships. Every check in the test
  passed throughout. The file check found it within a minute of first being
  pointed at a real set, which is the entire argument for exporting captures to
  disk instead of leaving them as attachments.
- **Explicitly not the answer:** cropping a fixed black margin, or any
  correction tuned to one device's proportions. The margin is an artefact of
  the wrong capture source, not something to trim off.
- **Fix:** both halves. The capture already uses `XCUIScreen.main.screenshot()`
  and asserts its own orientation. `scripts/screenshots.sh` now exports the
  attachments out of the result bundle into a directory, named from the
  manifest, and `scripts/screenshots-verify.py` checks them **as files**: right
  way up by name, no black band on any edge, nothing below App Store Connect's
  minimum. The `screenshots` and `screenshots_verify` lanes drive it and
  `release_check` fails when the set is missing.
- **The check deliberately refuses the easy fix.** Its failure message says the
  capture source is wrong and not to crop it, because a crop constant tuned to
  one device's proportions would make the symptom disappear and leave the
  defect (§43).
- **Verified by:** measured on disk, not in memory —
  `four-players-landscape.png` comes out **2752×2064** and
  `four-players-portrait.png` **2064×2752**. And the black-band check was
  exercised against a set that *does* carry bands — the letterboxed pane
  captures from `board-review.sh` — where it names them and gives the share of
  the frame. A check that has never fired is not a check.
- **Related files:** `App/KeezlyUITests/DesignReviewScreenshots.swift`,
  `scripts/screenshots.sh`, `scripts/screenshots-verify.py`

### ISS-011 — A commit message that does not match its content

- **Status:** OPEN (accepted; history will not be rewritten)
- **Severity:** Cosmetic
- **Component:** Repository history
- **Description:** Commit `1d46410`, "docs: record the iphone pass, the
  animation pipeline and a fresh device gate", contains only a regenerated
  `fastlane/README.md`. A patch script had aborted on a stale anchor before
  writing the documentation, and the commit was made without checking what had
  actually changed. The real documentation landed in `7022d9f`.
- **Impact:** None on the product. It makes that one commit misleading to read.
- **Decision:** The history stays as it is. Rewriting a pushed commit to tidy a
  message is a worse trade than a recorded blemish.
- **Prevention:** Patch scripts now report which anchors they failed to find,
  and a documentation commit is checked with `git show --stat` before pushing.

### ISS-010 — M4.7 cannot be verified end to end here

- **Status:** OPEN — blocked on equipment, not on code
- **Severity:** Verification gap (no known defect)
- **Component:** App / iPad input, test tooling
- **Description:** Pointer, trackpad and keyboard support is implemented and its
  logic is unit tested, but three things cannot be exercised on this machine:
  iOS only grants focus when a hardware keyboard or Full Keyboard Access is
  present; a simulator booted by `xcodebuild` has no keyboard attached; and this
  Xcode installation contains no `Simulator.app` to attach one through. No
  pointer or trackpad is available for the physical iPad either.
- **Reproduction:** `xcodebuild test -only-testing:KeezlyUITests/KeyboardPlayTests`
  — three tests skip with the reason.
- **Expected:** Arrow keys move focus in a running app.
- **Actual:** Focus stays where it is; no key event arrives.
- **Why it is not a defect:** the same code path is exercised by
  `PlayFocusTests`, and the focus state itself is verified on the simulator by
  forcing focus through the `-KEEZLY_FOCUS` launch argument. What is unproven is
  Apple's delivery of the key press, not Keezly's response to it.
- **Resolution:** carry out the hardware gate when a keyboard and a pointer are
  available. Recorded in `RELEASE_CHECKLIST.md` as NOT VERIFIED — HARDWARE NOT
  AVAILABLE, never as a pass.

---

## Closed

### ISS-009 — Landscape captures come out rotated

- **Status:** OPEN
- **Severity:** Minor (tooling; blocks App Store submission of captures)
- **Component:** Screenshot harness
- **Description:** `DesignReviewScreenshots` sets `XCUIDevice.orientation` and
  then takes `XCUIScreen.main.screenshot()`, which returns the physical screen
  buffer. The interface is correctly in landscape, but the image comes out in
  the device's portrait pixel orientation with the content turned on its side.
- **Reproduction:** Run any landscape capture and open the attachment.
- **Expected:** An image the right way up, submittable under §88.
- **Actual:** Correct content, rotated 90°.
- **Impact:** None on the design review — the board is fully legible and has
  been judged from these captures. It does matter for App Store screenshots,
  which is what the harness is ultimately for.
- **Workaround:** Rotate on export; not yet implemented.
- **Related files:** `App/KeezlyUITests/DesignReviewScreenshots.swift`

### ISS-008 — A two-player board has no quiet centre

- **Status:** VERIFIED (accepted, with the ornament suppressed)
- **Severity:** Minor (visual)
- **Component:** App / Board
- **Description:** The centre medallion was first sized in hole widths, which
  suits four and six seats. At two seats the track is half as long, so the home
  lanes run almost to the middle of the board: a medallion of that size would
  have been drawn straight across the deepest home square.
- **Reproduction:** `BoardOrnament.medallionRadius(innerField:square:)` with a
  two-seat layout's inner field.
- **Expected:** Ornament never overlaps the game.
- **Actual:** It would have, at two seats only.
- **Fix:** The medallion is measured against the board's own inner field and is
  **not drawn at all** when there is no room. Ornament over the game is worse
  than no ornament.
- **Remaining risk:** the same cramped centre also holds the draw pile and the
  turn indicator, which are sized from the view rather than from the board. A
  two-player table has not yet been reviewed for that crowding.
- **Related tests:** `BoardOrnamentTests.medallionFitsOrIsOmitted`,
  `BoardOrnamentTests.noRoomMeansNoMedallion`
- **Verified by:** the app suite at commit `8c9fa43`.

### ISS-007 — Dynamic Type had no effect anywhere in the interface

- **Status:** VERIFIED
- **Severity:** Major (accessibility)
- **Component:** App / UI
- **Description:** Every text style in the gameplay interface was a fixed
  `.system(size:)` derived from the board geometry, so the reader's text-size
  setting changed nothing at all. This is an accessibility failure rather than
  a cosmetic one (§53).
- **Reproduction:** Launch on any simulator with the content size category set
  to `accessibility-extra-large`; the interface is pixel-identical to the
  default.
- **Expected:** Chrome text grows with the reader's setting.
- **Actual:** Nothing moved.
- **Fix:** `@ScaledMetric` on the chrome — seat panels, seat chips, the turn
  indicator and the deal label. Card ranks and pips deliberately stay
  proportional to the card: a rank that outgrew its card would be less
  readable, not more. A second defect surfaced with the fix — the labels in the
  middle of the board were pinned to the pile width and truncated instead of
  wrapping — and was fixed by letting them wrap.
- **Related files:** `App/Keezly/Play/SeatStatusView.swift`,
  `App/Keezly/Board/BoardCentreView.swift`
- **Verified by:** screenshot captures at `accessibility-extra-large`, and the
  34/34 UI suite at commit `e4bae0f`.

### ISS-006 — Six seat panels clipped the board on iPhone

- **Status:** VERIFIED
- **Severity:** Major (layout)
- **Component:** App / UI
- **Description:** The phone layout reused the iPad's named seat panels. At six
  players the row of panels was wider than the screen, which widened the
  enclosing stack and pushed the board off the edge. A related defect: the wide
  layout was chosen by size class, but an iPhone in landscape can report a
  regular width, and deriving the board size from the height left after the
  hand produced a 149-point board on a 393-point screen.
- **Reproduction:** Launch with `-KEEZLY_SEATS 6` on an iPhone 17e (portrait),
  and rotate any iPhone to landscape.
- **Expected:** The board fits, on every phone, in both orientations.
- **Actual:** Clipped in portrait at six seats; unusably small in landscape.
- **Fix:** Phones get compact seat chips that drop the name — colour and mark
  already identify a seat, and identify it the same way on the board. The
  layout is chosen by the height actually available rather than by size class:
  below 520 points a short-and-wide arrangement gives the board the full height
  and puts the hand beside it. The seat row is also explicitly clipped to the
  screen width so an overflow can never widen the layout again.
- **Related files:** `App/Keezly/Play/GameScreen.swift`,
  `App/Keezly/Play/SeatStatusView.swift`
- **Verified by:** captures on iPhone 17e, iPhone 17 and iPhone 18 Pro Max in
  both orientations at four and six seats, and the 34/34 UI suite at commit
  `e4bae0f`.

### ISS-005 — Cancellation latency in the Hard agent

- **Status:** VERIFIED (and the original diagnosis was **wrong** — see below)
- **Severity:** Minor
- **Component:** `KeezlyCore` / AI

**What was observed.** `HardAgentTests.cancellationIsHonoured` failed
intermittently, reporting that a cancelled search took 5.2 seconds to return.
It passed when run alone and failed in the full suite.

**The first diagnosis was wrong.** It was attributed to `RolloutPolicy.playOut`
not checking `Task.isCancelled`, and checks were added. The failure persisted.

**The actual cause of the failure** was the measurement, not the agent. The
test timed the task from *outside*, so the five seconds were the global
executor queueing the task under a parallel test run — not the agent working.
Two things made this hard to see:

1. The test positions were fresh deals, where the acting seat often has one or
   two legal moves. `HardAgent` short-circuits on `candidates.count > 1` and
   returns before sampling at all, so the search under test never actually ran.
2. Removing *every* cancellation check left the measurement unchanged, which is
   what finally showed the test was not exercising what it claimed.

**What was real.** On a position that genuinely loads the search — six seats,
four pawns out, a Seven in hand, 108 legal moves — the cancellation checks do
matter, though less dramatically than first thought:

| | Time spent working after cancel |
|---|---:|
| with the checks | ~2 ms |
| without them | ~31 ms |

**Resolution.**
- The cancellation checks stay: cheap, and a measured ~16× improvement.
- The tests were rebuilt on the heavy position, timed *inside* the task, with
  `heavyPositionIsActuallyHeavy` guarding that the position stays expensive so
  the guarantee cannot quietly stop being tested.
- `AI.md` now separates average-case from worst-case timing, because quoting
  the ~16 ms average alone was misleading: on a heavy position Hard uses its
  full 700 ms budget.

**Lesson recorded here on purpose:** a green performance test on a position the
code short-circuits out of proves nothing. The mutation check — remove the
mechanism, see whether the test notices — is what caught it.

**Related files:** `Sources/KeezlyCore/AI/RolloutPolicy.swift`,
`Sources/KeezlyCore/AI/HardAgent.swift`, `Sources/KeezlyCore/AI/MovePreview.swift`
**Related tests:** `HardAgentTests.cancellationMidSearchIsHonoured`,
`.cancellationBeforeStartIsHonoured`, `.heavyPositionIsActuallyHeavy`

### ISS-004 — Apple Developer team ids were committed to documentation

- **Status:** FIXED (working tree) — see "remaining exposure" below
- **Severity:** Low
- **Component:** Documentation / process
- **Description:** While recording the signing decision, two Apple Developer
  team ids were written into `CURRENT_STATE.md`, contradicting DEC-013, which
  says account-specific signing configuration never enters the repository.
- **How it was caught:** the repository-wide secret sweep that runs after
  credential work, not by review. The sweep is worth keeping for that reason.
- **Fix:** both ids removed from all tracked files; the team id now exists only
  in the git-ignored `Config/Local.xcconfig`.
- **Remaining exposure:** the ids are still present in pushed history, in
  commit `497accf`. An Apple **Team ID is an identifier, not a credential** — it
  appears in every shipped app's provisioning profile and cannot be used to
  authenticate — so the practical risk is negligible. Removing it entirely would
  need a history rewrite and a force push, which is the repository owner's call.
- **Not affected:** the App Store Connect **key id, issuer id and `.p8` private
  key never entered the repository** at any point. They live outside it, and the
  swept files confirm that.
- **Related files:** `CURRENT_STATE.md`, `Config/Local.xcconfig` (untracked),
  `DECISIONS.md` → DEC-013

### ISS-001 — Move generator failed to compile due to name shadowing

- **Status:** VERIFIED
- **Severity:** Blocker (build)
- **Component:** `KeezlyCore` / Engine
- **Description:** A local variable `moves` shadowed the private
  `moves(in:seat:card:)` function, so the recursive call was parsed as a
  subscript on an array.
- **Reproduction:** `swift build` at the time of writing `MoveGenerator.swift`.
- **Expected:** Compiles.
- **Actual:** `error: cannot call value of non-function type '[Move]'`.
- **Fix:** Renamed the function to `generateMoves(in:seat:card:)`.
- **Related files:** `Packages/KeezlyCore/Sources/KeezlyCore/Engine/MoveGenerator.swift`
- **Verified by:** `swift build` and the full suite at commit `64931ef`.

### ISS-002 — Jack could target a seat with no pawns of its own on the track

- **Status:** VERIFIED
- **Severity:** Major (rule correctness)
- **Component:** `KeezlyCore` / Engine
- **Description:** `swapActions` excluded swap targets by comparing against the
  acting player's pawns *that were currently on the track*, rather than against
  the set of seats the player controls. When a controlled seat had no pawn on
  the track, that seat's own pawns became valid swap targets.
- **Reproduction:** Found by inspection before it reached a test run; would have
  surfaced as a finished player being able to swap their partner's pawns against
  each other.
- **Expected:** A Jack always trades one of your pawns for a *different* seat's.
- **Actual:** Could have targeted a controlled seat's own pawn.
- **Fix:** Exclude targets by `controllableSeats(for:)` instead.
- **Related files:** `Packages/KeezlyCore/Sources/KeezlyCore/Engine/MoveGenerator.swift`
- **Related tests:** `CardRuleTests.jackMayTargetPartner`,
  `CardRuleTests.jackRespectsProtectionAndHome`
- **Verified by:** full suite at commit `64931ef`.

### ISS-003 — Degenerate test fixture masked correct redeal behaviour

- **Status:** VERIFIED
- **Severity:** Minor (test only, not a product defect)
- **Component:** Tests
- **Description:** `foldingIsAllowedWhenNothingIsPlayable` built a state where
  *every* seat had an unplayable or empty hand. The engine correctly concluded
  that the deal round was over and started a new one, which clears the folded
  set by design — so the assertion on `foldedSeats` failed.
- **Expected:** The test asserts the fold, not the redeal.
- **Actual:** The fixture forced an immediate redeal.
- **Fix:** Give a second seat a playable card so the round continues. The engine
  was not changed; it was already right.
- **Related files:** `Packages/KeezlyCore/Tests/KeezlyCoreTests/GameFlowTests.swift`
- **Verified by:** full suite at commit `64931ef`.
