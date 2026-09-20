# Keezly — Game Center Multi-Device Test Plan

Game Center multiplayer may **not** be marked `VERIFIED` on the strength of
mocks and simulators alone (§168). At least one real end-to-end constellation
across two physical devices must pass.

Valid constellations: iPhone ↔ iPad, iPhone ↔ iPhone, iPad ↔ iPad. Devices are
addressed by role (`PRIMARY_IPHONE`, `SECONDARY_IPHONE`, `PRIMARY_IPAD`,
`SECONDARY_IPAD`) — see `docs/DEVICE_TESTING.md`.

Status values: `NOT RUN` · `PASSED` · `FAILED` · `BLOCKED`.

---

## Prerequisites

| # | Requirement | Status |
|---|---|---|
| 1 | Game Center implemented in the app | **NOT IMPLEMENTED** (M6) |
| 2 | Two physical iOS devices paired with this Mac | **BLOCKED** — none paired |
| 3 | Two distinct Apple Accounts signed into Game Center | OPEN |
| 4 | Game Center capability enabled for the bundle id | OPEN (MAN-05) |
| 5 | App Store Connect app record | OPEN (MAN-02) |

Every test below is therefore currently `BLOCKED`. None has been attempted, and
none may be recorded as anything else until it actually runs (§138, §151).

---

## Test cases

| ID | Test | Devices | Status | Last run | Commit |
|---|---|---|---|---|---|
| GC-DEVICE-001 | Authentication — sign in, sign out, signed-out fallback to local play | any | BLOCKED | — | — |
| GC-DEVICE-002 | Friend match — invite, accept, match starts | 2 | BLOCKED | — | — |
| GC-DEVICE-003 | Automatch — both devices queue and are paired | 2 | BLOCKED | — | — |
| GC-DEVICE-004 | Turn transfer — A plays, B receives the turn and sees the same board | 2 | BLOCKED | — | — |
| GC-DEVICE-005 | Resume after app kill — force-quit mid-match, relaunch, state intact | 2 | BLOCKED | — | — |
| GC-DEVICE-006 | Resume after device lock — lock during opponent's turn, unlock | 2 | BLOCKED | — | — |
| GC-DEVICE-007 | Network loss — airplane mode during a turn submission | 2 | BLOCKED | — | — |
| GC-DEVICE-008 | Reconnect — network returns, no duplicated or lost turn | 2 | BLOCKED | — | — |
| GC-DEVICE-009 | Quit match — resignation propagates, policy applied correctly | 2 | BLOCKED | — | — |
| GC-DEVICE-010 | Victory — match ends, both devices agree on the result | 2 | BLOCKED | — | — |
| GC-DEVICE-011 | Rematch — accepted from the finished match | 2 | BLOCKED | — | — |
| GC-DEVICE-012 | iPhone ↔ iPad — a full match across device classes | 2 | BLOCKED | — | — |
| GC-DEVICE-013 | Different supported OS versions on each endpoint | 2 | BLOCKED | — | — |
| GC-DEVICE-014 | Six-player state serialisation stays within `matchDataMaximumSize` | 2+ | BLOCKED | — | — |

---

## Method notes

**GC-DEVICE-004 (turn transfer)** is the core correctness test. Both devices
must agree on the complete board *and* on the revision counter. A mismatch here
means the online envelope or the revision guard is wrong, not the UI.

**GC-DEVICE-007/008 (network)** exist to prove idempotency (§28, §63). The
specific failure to hunt for is a turn applied twice after a retry, which would
show as a pawn jumping two moves' worth of squares. Submit a turn with the
network down, restore it, and confirm exactly one application.

**GC-DEVICE-014 (size)** needs no opponent interaction: build a six-player
state deep into a match, encode it, and assert the byte count against
`match.matchDataMaximumSize` before any upload is attempted.

**GC-DEVICE-013 (OS versions)** requires two devices on different iOS releases.
If only one OS version is available, this is `BLOCKED`, not `PASSED`.

---

## Recording a result

When a test runs, replace its row's status, date and commit, and mirror the
summary into `CURRENT_STATE.md` → Device Verification. A failure additionally
gets an entry in `KNOWN_ISSUES.md` noting whether it reproduces against the
mocked Game Center service (§174).
