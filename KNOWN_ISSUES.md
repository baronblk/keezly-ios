# Keezly — Known Issues

Register of reproducible technical problems (§137). Status values:
`OPEN`, `INVESTIGATING`, `FIXED`, `VERIFIED`. An issue only becomes `VERIFIED`
after a test has actually been run and passed.

Open work that is not a defect belongs in `ROADMAP.md`, not here (§141).

---

## Open

*None.*

---

## Closed

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
