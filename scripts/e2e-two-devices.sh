#!/bin/bash
#
# Runs the physical quick-match test on both connected devices at the same
# time and decides the gate from what the two devices actually logged.
#
# The point is that automatch needs two devices searching together. Running the
# test on one device and then the other proves nothing: by the time the second
# starts, the first has already been handed a match of its own.
#
# Devices are found by hardware reality, never by name or a remembered UDID —
# a booted simulator reports as connected and would otherwise be picked up.
# No identifier is written to the report.
#
#   scripts/e2e-two-devices.sh [seats]
#
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SEATS="${1:-2}"
OUT="${E2E_OUT:-/tmp/keezly-e2e}"
mkdir -p "$OUT"
A_LOG="$OUT/A.log"
B_LOG="$OUT/B.log"
REPORT="$OUT/report.txt"
: > "$REPORT"

say() { printf '%s\n' "$*" | tee -a "$REPORT"; }

# ---------------------------------------------------------------- devices ---

xcrun devicectl list devices --json-output "$OUT/devices.json" >/dev/null 2>&1

# KEEZLY_DEVICE_A / KEEZLY_DEVICE_B pin the run to particular devices. Worth
# having: which devices are wired changes between sessions, and an automatch
# test that silently swapped in a third device would be measuring nothing.

read -r A_ID A_NAME A_LINK < <(python3 - "$OUT/devices.json" iPhone <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
want = sys.argv[2].lower()

# Wired first. A device on localNetwork can be picked up, but it is slower and
# drops out mid-run, and a test that dies halfway proves nothing. Reported
# either way so the run says which link it used.
candidates = []
for dev in data.get("result", {}).get("devices", []):
    hw, cp = dev.get("hardwareProperties", {}), dev.get("connectionProperties", {})
    if hw.get("reality") != "physical" or cp.get("tunnelState") != "connected":
        continue
    name = (hw.get("marketingName") or "")
    if want not in name.lower():
        continue
    wired = cp.get("transportType") == "wired"
    candidates.append((0 if wired else 1, dev["identifier"], name, cp.get("transportType") or "?"))

if candidates:
    candidates.sort()
    _, ident, name, transport = candidates[0]
    print(ident, name, transport)
PY
)

read -r B_ID B_NAME B_LINK < <(python3 - "$OUT/devices.json" iPad <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
want = sys.argv[2].lower()

# Wired first. A device on localNetwork can be picked up, but it is slower and
# drops out mid-run, and a test that dies halfway proves nothing. Reported
# either way so the run says which link it used.
candidates = []
for dev in data.get("result", {}).get("devices", []):
    hw, cp = dev.get("hardwareProperties", {}), dev.get("connectionProperties", {})
    if hw.get("reality") != "physical" or cp.get("tunnelState") != "connected":
        continue
    name = (hw.get("marketingName") or "")
    if want not in name.lower():
        continue
    wired = cp.get("transportType") == "wired"
    candidates.append((0 if wired else 1, dev["identifier"], name, cp.get("transportType") or "?"))

if candidates:
    candidates.sort()
    _, ident, name, transport = candidates[0]
    print(ident, name, transport)
PY
)

A_ID="${KEEZLY_DEVICE_A:-${A_ID:-}}"
B_ID="${KEEZLY_DEVICE_B:-${B_ID:-}}"

if [ -z "${A_ID:-}" ] || [ -z "${B_ID:-}" ]; then
  say "BLOCKED: need one physical iPhone and one physical iPad, both wired."
  say "  iPhone: ${A_NAME:-not found}"
  say "  iPad:   ${B_NAME:-not found}"
  exit 2
fi

say "=============================================================="
say "KEEZLY PHYSICAL E2E — quick match, ${SEATS} seats"
say "$(date '+%Y-%m-%d %H:%M:%S')"
say "=============================================================="
say "DEVICE A  $A_NAME  (${A_LINK:-?})"
say "DEVICE B  $B_NAME  (${B_LINK:-?})"
say ""

# ------------------------------------------------------------------- run ---


# Each device gets its own DerivedData. Two concurrent xcodebuilds sharing one
# lock the build database and the second dies with "database is locked" — which
# looks like a test failure and is not one.
dd_for() { echo "$OUT/dd-$1"; }

prebuild() {                     # $1 = udid, $2 = logfile, $3 = label
  say "Building for device $3 …"
  xcodebuild build-for-testing \
    -project Keezly.xcodeproj -scheme Keezly \
    -destination "platform=iOS,id=$1" \
    -derivedDataPath "$(dd_for "$3")" \
    -testPlan Keezly-Physical \
    -allowProvisioningUpdates -quiet \
    > "$2" 2>&1
  local status=$?
  echo "BUILD EXIT $status" >> "$2"
  return $status
}

run_on() {                       # $1 = udid, $2 = logfile, $3 = label
  xcodebuild test-without-building \
    -project Keezly.xcodeproj -scheme Keezly \
    -destination "platform=iOS,id=$1" \
    -derivedDataPath "$(dd_for "$3")" \
    -testPlan Keezly-Physical \
    >> "$2" 2>&1
  echo "EXIT $?" >> "$2"
}

# Built one at a time, on purpose: building is slow and uneven, and if it
# happened inside the parallel phase the two devices would start searching
# minutes apart — which is exactly the thing automatch cannot survive.
prebuild "$A_ID" "$A_LOG" A
A_BUILD=$?
prebuild "$B_ID" "$B_LOG" B
B_BUILD=$?

if [ "$A_BUILD" -ne 0 ] || [ "$B_BUILD" -ne 0 ]; then
  say ""
  if grep -qh "Unlock .* to Continue" "$A_LOG" "$B_LOG"; then
    say "OWNER STEP REQUIRED: a device is locked. Unlock it and re-run — nothing"
    say "about matchmaking has been tested."
    grep -hoE "Unlock [^\"]+ to Continue" "$A_LOG" "$B_LOG" | sort -u | tee -a "$REPORT"
    exit 4
  fi
  say "BLOCKED: could not build for one of the devices (A=$A_BUILD B=$B_BUILD)."
  grep -hE "error:" "$A_LOG" "$B_LOG" | sort -u | head -5 | tee -a "$REPORT"
  exit 3
fi

# How long B waits before it starts searching.
#
# Simultaneous is the obvious choice and is probably wrong. `GKTurnBasedMatch
# .find` does not queue and wait: it looks for a joinable match and otherwise
# creates one there and then. Two devices calling it in the same instant cannot
# see each other's match yet, so both create their own — which is exactly what
# the first clean-account run showed, two different ids at 1/2 each.
#
# A stagger gives A's match time to exist before B goes looking for one.
# Set KEEZLY_E2E_STAGGER=0 to go back to simultaneous and compare.
STAGGER="${KEEZLY_E2E_STAGGER:-20}"

say ""
if [ "$STAGGER" -gt 0 ]; then
  say "A starts now; B follows after ${STAGGER}s, so A's match exists to be found."
else
  say "Both devices start at once."
fi
run_on "$A_ID" "$A_LOG" A &
PID_A=$!
if [ "$STAGGER" -gt 0 ]; then sleep "$STAGGER"; fi
run_on "$B_ID" "$B_LOG" B &
PID_B=$!
wait $PID_A; wait $PID_B
say ""

# ---------------------------------------------------------------- verdict ---

python3 - "$A_LOG" "$B_LOG" "$SEATS" <<'PY' | tee -a "$REPORT"
import re, sys

a_log, b_log, seats = open(sys.argv[1], errors="replace").read(), open(sys.argv[2], errors="replace").read(), int(sys.argv[3])

def find(text, pattern):
    return re.findall(pattern, text)

def gate(name, ok, detail=""):
    mark = "PASS" if ok is True else ("FAIL" if ok is False else "NOT TESTED")
    print(f"{name:<24} {mark:<12} {detail}")
    return ok

print("GATE                     RESULT       DETAIL")
print("-" * 78)

# First, and hardest: did anything run at all?
#
# Three times now this project has produced a green run that tested nothing —
# a plan that skipped the suite, an `-only-testing` that matched no method, and
# an edit that never reached the file. Each time xcodebuild reported success.
# A gate table full of NOT TESTED is too easy to skim past, so the executed
# count is checked first and fails loudly.
for label, log in (("A", a_log), ("B", b_log)):
    ran = re.findall(r"Executed (\d+) tests?", log)
    count = max((int(n) for n in ran), default=0)
    gate(f"TESTS RAN {label}", count > 0,
         f"{count} test(s) executed" if count else "NOTHING RAN — every gate below is meaningless")


# Authentication, from the app's own log rather than from an assumption.
a_auth = "auth=true" in a_log
b_auth = "auth=true" in b_log
gate("AUTH A", a_auth or None, "" if a_auth else "no authenticated=true line; device may be signed out")
gate("AUTH B", b_auth or None, "" if b_auth else "no authenticated=true line; device may be signed out")

# The requests, compared field by field.
a_req = find(a_log, r"request kind=quickMatch (.+)")
b_req = find(b_log, r"request kind=quickMatch (.+)")
if a_req and b_req:
    same_req = a_req[-1].strip() == b_req[-1].strip()
    gate("MATCH REQUEST", same_req, "identical" if same_req else "DIFFER — see diff below")
    if not same_req:
        print(f"\n  A: {a_req[-1].strip()}\n  B: {b_req[-1].strip()}\n")
else:
    gate("MATCH REQUEST", None, "no quickMatch request logged on one or both devices")

# The line that decides it.
a_match = find(a_log, r"match=(\S+) filled=")
b_match = find(b_log, r"match=(\S+) filled=")
if a_match and b_match:
    same = a_match[-1] == b_match[-1]
    gate("SAME MATCH", same,
         "both devices landed in one match" if same
         else "DIFFERENT matches — automatch did not pair the two requests")
else:
    gate("SAME MATCH", None, f"A got {len(a_match)} match(es), B got {len(b_match)}")

# Seats filled.
def filled(text):
    got = find(text, r"filled=(\d+)/(\d+)")
    return (int(got[-1][0]), int(got[-1][1])) if got else None

a_fill, b_fill = filled(a_log), filled(b_log)
full = bool(a_fill and b_fill and a_fill[0] == a_fill[1] == seats and b_fill[0] == b_fill[1] == seats)
gate("FILLED", full if (a_fill and b_fill) else None,
     f"A={a_fill[0]}/{a_fill[1]} B={b_fill[0]}/{b_fill[1]}" if (a_fill and b_fill) else "no participant line")

# Exactly one device may deal.
deals = len(find(a_log, r"board dealt")) + len(find(b_log, r"board dealt"))
gate("EXACTLY ONE DEAL", (deals == 1) if deals else None,
     f"{deals} deal(s) across both devices" + (" — a double deal" if deals > 1 else ""))

# Same position on both.
def boards(text):
    return {(int(rev), cks) for rev, cks in find(text, r"board \w+ match=\S+ revision=(\d+) checksum=(\w+)")}

a_boards, b_boards = boards(a_log), boards(b_log)
shared_revs = {r for r, _ in a_boards} & {r for r, _ in b_boards}
if shared_revs:
    mismatched = [
        rev for rev in shared_revs
        if {c for r, c in a_boards if r == rev} != {c for r, c in b_boards if r == rev}
    ]
    gate("SAME CHECKSUM", not mismatched,
         f"{len(shared_revs)} shared revision(s)" if not mismatched
         else f"diverged at revision(s) {sorted(mismatched)}")
else:
    gate("SAME CHECKSUM", None, "no revision seen on both devices")

# Turns.
a_moves = len(find(a_log, r"move accepted"))
b_moves = len(find(b_log, r"move accepted"))
gate("A -> B TURN", (a_moves > 0) if a_moves else None, f"{a_moves} move(s) accepted on A")
gate("B -> A TURN", (b_moves > 0) if b_moves else None, f"{b_moves} move(s) accepted on B")
gate("KILL/RESUME", None, "not attempted in this run")

print("-" * 78)
for label, log in (("A", a_log), ("B", b_log)):
    fails = find(log, r"(OWNER STEP:[^\n]+)")
    for f in fails:
        print(f"OWNER STEP on {label}: {f}")
    for err in set(find(log, r"FAILED domain=(\S+) code=(-?\d+)")):
        print(f"GameKit error on {label}: domain={err[0]} code={err[1]}")
PY

say ""
say "Full logs: $A_LOG  $B_LOG"
