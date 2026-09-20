# Keezly — Known Issues

Register of reproducible technical problems (§137). Status values:
`OPEN`, `INVESTIGATING`, `FIXED`, `VERIFIED`. An issue only becomes `VERIFIED`
after a test has actually been run and passed.

Open work that is not a defect belongs in `ROADMAP.md`, not here (§141).

---

## Open

| # | Summary | Severity |
|---|---|---|
| ISS-009 | Landscape captures come out rotated | Minor (tooling) |
| ISS-010 | No hardware keyboard or pointer available to verify M4.7 end to end | Verification gap |
| ISS-011 | Commit `1d46410` carries a message that does not match its content | Cosmetic (history) |

---

## Closed

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
