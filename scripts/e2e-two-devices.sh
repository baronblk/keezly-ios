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

read -r A_ID A_NAME < <(python3 - "$OUT/devices.json" iPhone <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
want = sys.argv[2]
for dev in data.get("result", {}).get("devices", []):
    hw, cp, dp = dev.get("hardwareProperties", {}), dev.get("connectionProperties", {}), dev.get("deviceProperties", {})
    if hw.get("reality") != "physical" or cp.get("tunnelState") != "connected":
        continue
    if want.lower() in (hw.get("marketingName") or "").lower():
        print(dev["identifier"], hw.get("marketingName"))
        break
PY
)

read -r B_ID B_NAME < <(python3 - "$OUT/devices.json" iPad <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
want = sys.argv[2]
for dev in data.get("result", {}).get("devices", []):
    hw, cp, dp = dev.get("hardwareProperties", {}), dev.get("connectionProperties", {}), dev.get("deviceProperties", {})
    if hw.get("reality") != "physical" or cp.get("tunnelState") != "connected":
        continue
    if want.lower() in (hw.get("marketingName") or "").lower():
        print(dev["identifier"], hw.get("marketingName"))
        break
PY
)

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
say "DEVICE A  $A_NAME"
say "DEVICE B  $B_NAME"
say ""

# ------------------------------------------------------------------- run ---

run_on() {                       # $1 = udid, $2 = logfile, $3 = label
  xcodebuild test \
    -project Keezly.xcodeproj -scheme Keezly \
    -destination "platform=iOS,id=$1" \
    -only-testing:KeezlyUITests/QuickMatchPhysicalTests/testQuickMatchTwoPlayers \
    -allowProvisioningUpdates \
    > "$2" 2>&1
  echo "EXIT $?" >> "$2"
}

say "Running on both devices at once — automatch needs them searching together."
run_on "$A_ID" "$A_LOG" A &
PID_A=$!
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

# Authentication, from the app's own log rather than from an assumption.
a_auth = "authenticated=true" in a_log
b_auth = "authenticated=true" in b_log
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
a_match = find(a_log, r"matched id=(\S+)")
b_match = find(b_log, r"matched id=(\S+)")
if a_match and b_match:
    same = a_match[-1] == b_match[-1]
    gate("SAME MATCH", same,
         "both devices landed in one match" if same
         else "DIFFERENT matches — automatch did not pair the two requests")
else:
    gate("SAME MATCH", None, f"A got {len(a_match)} match(es), B got {len(b_match)}")

# Seats filled.
def filled(text):
    got = find(text, r"participants filled=(\d+) of=(\d+)")
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
