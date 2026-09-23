# Keezly — Rule Variant Matrix

Keezen is a traditional game with regional and family variation. This file
records **which rule Keezly implements, why, and how it is configured** (§75,
§144). Rule texts here are written from scratch; no rule text is copied from
another publisher or website (§76).

Where sources disagree, the disagreement is written down and solved as a
configuration option — never guessed silently.

Legend for the *Engine* column: the `RuleSet` property and case.

---

## RULE-001 — Ace

| | |
|---|---|
| **Topic** | What an Ace may do |
| **Keezly Classic** | Bring a pawn out of the waiting area onto your start square, **or** advance one square |
| **Tournament** | Same |
| **House rule options** | none |
| **Engine** | hard-coded in `MoveGenerator` |
| **Tests** | `CardRuleTests.aceOffersBothOptions`, `.enterUsesOwnStart` |

**Source / interpretation.** Consistent across every description consulted.

---

## RULE-002 — King

| | |
|---|---|
| **Topic** | What a King may do |
| **Keezly Classic** | Bring a pawn out only |
| **Tournament** | Bring a pawn out only |
| **House rule options** | Bring out **or** advance 13 |
| **Engine** | `RuleSet.king` — `.enterOnly` / `.enterOrAdvance13` |
| **Tests** | `CardRuleTests.kingIsEnterOnlyByDefault`, `.kingAdvancesThirteenWhenConfigured` |

**Source / interpretation.** The "start only" reading is the traditional one and
is the default. The "+13" reading is widespread in family play and is offered as
a house rule rather than being treated as the standard.

---

## RULE-003 — Queen

| | |
|---|---|
| **Topic** | Queen movement |
| **Keezly Classic** | Exactly 12 forward |
| **Tournament** | Same |
| **Engine** | hard-coded |
| **Tests** | `CardRuleTests.queenMovesTwelve` |

---

## RULE-004 — Jack

| | |
|---|---|
| **Topic** | Swapping pawns |
| **Keezly Classic** | Exchange one of your own active pawns with an active pawn of **another seat**, including a partner's. The target may not be protected on its own start square and may not be in a home lane. |
| **Tournament** | Same |
| **House rule options** | Whether a pawn standing on its *own* protected start square may act as the swap **source** |
| **Engine** | `RuleSet.jackOwnStart` — `.mayNotBeSwapSource` (default) / `.mayBeSwapSource` |
| **Tests** | `CardRuleTests.jackSwapsPositions`, `.jackMayTargetPartner`, `.jackRespectsProtectionAndHome`, `.jackOwnStartPolicyIsHonoured` |

**Source / interpretation.** That a protected pawn cannot be *taken* is
universal. Whether it may *initiate* a swap — voluntarily giving up its own
protection — is genuinely inconsistent between descriptions. Keezly defaults to
the stricter reading (protection is absolute in both directions) and offers the
permissive reading as a house rule. **This is the main open question in the
matrix.**

---

## RULE-005 — Home entry

| | |
|---|---|
| **Topic** | Getting into the home lane |
| **Keezly Classic** | Exact count required. A count that would overshoot the deepest home square is simply not a legal move — the pawn cannot take another lap to avoid the problem. |
| **Tournament** | Same |
| **House rule options** | "Extra lap": the pawn may ride past its own entry and continue on the track |
| **Engine** | `RuleSet.homeEntry` — `.exactCountOnly` (default) / `.allowExtraLap` |
| **Tests** | `CardRuleTests.homeRequiresExactCount`; variant covered by `InvariantTests.ruleVariantsSelfPlay` |

**Source / interpretation — UNRESOLVED, needs play-testing.** The extra-lap
variant is under-specified in every description consulted: it is not clear
whether passing your own entry is *optional* (a choice) or *forced* when the
count does not fit. Keezly implements it as an explicit choice: when both are
legal, the player is offered both routes, modelled as `AdvanceRoute.standard`
vs `.stayOnTrack`. Recorded as DEC-005. **Must be play-tested before 1.0.0.**

---

## RULE-006 — Home ordering

| | |
|---|---|
| **Topic** | Which home square a pawn may occupy |
| **Keezly Classic** | Any home square reachable with an exact count, provided the pawn does not jump over a pawn already home |
| **Tournament** | Same |
| **House rule options** | Strictly fill from the deepest square forward |
| **Engine** | `RuleSet.homeOrdering` — `.anyReachableWithoutJumping` (default) / `.strictBackToFront` |
| **Tests** | `CardRuleTests.homePawnsCannotBeJumped`, `.strictHomeOrdering` |

---

## RULE-007 — Protected start square

| | |
|---|---|
| **Topic** | The blockade on your own start square |
| **Keezly Classic** | A pawn standing on its own start square cannot be captured, cannot be passed by any pawn in either direction, and cannot be the target of a Jack. It is a genuine blockade. |
| **Tournament** | Same |
| **House rule options** | none |
| **Engine** | `GameState.isProtected(_:)` + `MoveResolver.blocksPassage` |
| **Tests** | `CardRuleTests.protectedStartIsAnAbsoluteBlockade`, `.ownStartBlocksEntering`, `.enteringCapturesSquatter`, `.fourIsStoppedByABlockade` |

**Source / interpretation.** Some descriptions protect only a *freshly placed*
pawn. Keezly implements the simpler and more commonly described rule: occupying
your own start square confers protection for as long as the pawn stands there.
Noted here so the choice stays visible.

---

## RULE-008 — Four

| | |
|---|---|
| **Topic** | Backward movement |
| **Keezly Classic** | Exactly four squares backward along the shared track. Never into a home lane, never out of one, and it may not cross a protected start square. |
| **Tournament** | Same |
| **House rule options** | none |
| **Engine** | `MoveResolver.resolveBackward` — backward is computed on raw track indices, so a home lane is unreachable by construction |
| **Tests** | `CardRuleTests.fourMovesBackward`, `.fourCannotLeaveHome`, `.fourCannotEnterHome`, `.fourIsStoppedByABlockade`, and `MoveDirectionTests` for the exclusivity below |

**The Four is the only backward card.** That is not a variant and there is no
option that changes it. Every other rank that moves a pawn moves it forward, and
a Seven's every partial leg is forward too. `MoveDirectionTests` measures this
as the pawn's own progress rather than as a track index — on a ring a smaller
index is not "behind" — across every rank at every table size from two to six
seats, including the wrap-around and the home entry. See `RULES.md`, *Direction
— the canonical statement*.

---

## RULE-009 — Seven

| | |
|---|---|
| **Topic** | Splitting seven steps |
| **Keezly Classic** | Exactly seven steps, spent either entirely by one pawn or split across two pawns (1+6, 2+5, 3+4 and the reverse orders). Every step must be used and each leg must be legal on the board the previous leg leaves behind. |
| **Tournament** | Same |
| **House rule options** | none |
| **Engine** | `MoveGenerator.splitActions` — enumerates complete sequences only |
| **Tests** | `CardRuleTests.sevenSplitsAreWellFormed`, `.sevenEnumeratesAllSplits`, `.sevenCrossesToPartnerAfterFinishing` |

**Interpretation.** "Split across two pawns" is read as *at most two legs*,
matching the 1+6 / 2+5 / 3+4 enumeration in the specification. A three-leg
sequence using two pawns is therefore not offered.

The generator produces only sequences that can be completed, so the UI can
never lead a player into a dead end with steps left over (§38).

---

## RULE-010 — Capturing, including friendly fire

| | |
|---|---|
| **Topic** | Landing on an occupied square |
| **Keezly Classic** | Landing on an unprotected pawn sends it back to its waiting area — including your own pawn and your partner's. Combined with the forced-move rule this can be unavoidable. |
| **Tournament** | Same |
| **House rule options** | Landing on a friendly pawn is illegal instead |
| **Engine** | `RuleSet.friendlyCapture` — `.captureAllowed` (default) / `.landingForbidden` |
| **Tests** | `CardRuleTests.capturingAnOpponent`, `.friendlyCaptureIsAllowedByDefault`, `.friendlyCaptureCanBeForbidden` |

---

## RULE-011 — Own pawns as obstacles

| | |
|---|---|
| **Topic** | Whether your own non-protected pawns block the track |
| **Keezly Classic** | No — only protected start squares and occupied home squares block |
| **Tournament** | Same |
| **House rule options** | Own pawns form blockades as well |
| **Engine** | `RuleSet.ownPawnBlocking` — `.passable` (default) / `.blocking` |
| **Tests** | variant covered by `InvariantTests.ruleVariantsSelfPlay` |

---

## RULE-012 — Forced move

| | |
|---|---|
| **Topic** | Must a legal move be played? |
| **Keezly Classic** | Yes. If any card in hand yields any legal move, one must be played, however bad. Only when the entire hand is dead may it be thrown in — and that seat then sits out the rest of the deal round. |
| **Tournament** | Same |
| **House rule options** | none |
| **Engine** | `MoveGenerator.hasAnyLegalMove` + `GameReducer.applyFold`; the reducer rejects a fold while a move exists |
| **Tests** | `GameFlowTests.foldingIsAllowedWhenNothingIsPlayable`, `.foldingIsRejectedWhenAMoveExists`, `.deadHandsAreFoldedWhilePassingTheTurn`, `InvariantTests.generatorAndReducerAgree` |

---

## RULE-013 — Dealing

| | |
|---|---|
| **Topic** | The 5/4/4 cycle |
| **Keezly Classic** | Three rounds of 5, 4 and 4 cards per seat — 13 in total, exactly exhausting a deck of 13 cards per seat. Then reshuffle, rotate the dealer, and repeat. The player to the dealer's left opens. |
| **Tournament** | Same |
| **Engine** | `DealState`, `GameState.advanceDealRound()` |
| **Tests** | `GameFlowTests.fullCycleExhaustsDeck`, `.dealerRotatesBetweenCycles`, `.firstTurnIsLeftOfDealer`, `.deckSizeScalesWithTable` |

---

## RULE-014 — Team play and partner continuation

| | |
|---|---|
| **Topic** | What happens once your own pawns are all home |
| **Keezly Classic** | You keep playing with your partner's pawns. A team wins when every seat on it has all four pawns home. |
| **Tournament** | Same |
| **Engine** | `GameState.controllableSeats(for:)`, `GameReducer.evaluateVictory` |
| **Tests** | `CardRuleTests.sevenCrossesToPartnerAfterFinishing`, `GameFlowTests.teamVictoryNeedsBothPartners` |

Default seating: with 4 seats, 0+2 against 1+3; with 6 seats, 0+3, 1+4 and 2+5.
Partners always sit opposite each other, which `GameConfiguration.team(of:)`
guarantees by construction.

---

## RULE-015 — Resignation

| | |
|---|---|
| **Topic** | Leaving a match |
| **Keezly Classic** | In team play, a resignation forfeits the whole team. In free-for-all the player is removed, their pawns leave the track so they stop blocking, and the others play on; the last remaining player wins. |
| **Engine** | `GameReducer.applyResign` |
| **Tests** | `GameFlowTests.resigningForfeitsTheTeam`, `.resigningInFreeForAllLeavesOthersPlaying` |

This is a product policy rather than a traditional rule, and is documented as
such (§30).

---

## Tournament preset — status

The **Tournament** preset currently equals **Keezly Classic** in every row above.

This is deliberate. §18 requires that only *verified* tournament rules are
adopted, and no primary rule source has been checked yet. Inventing differences
to make the preset look distinct would be worse than an honest identity. The
preset exists so that matches created under it carry the right label and can be
migrated when the real differences are confirmed.

**Open action:** verify current Dutch tournament rules against a primary source
and update this matrix before 1.0.0. Tracked in `ROADMAP.md` (M12) and in
`CURRENT_STATE.md` under Technical Risks.
