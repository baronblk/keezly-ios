#!/usr/bin/env bash
#
# Keezly device discovery.
#
# Finds the physical iPhones and iPads currently paired with this Mac and maps
# them onto stable *roles* — PRIMARY_IPHONE, SECONDARY_IPHONE, PRIMARY_IPAD,
# SECONDARY_IPAD — so that scripts, lanes and test runs never hard-code a
# device name or UDID (§158, §176).
#
# Nothing this script discovers is ever written into the repository. UDIDs are
# printed to stdout for immediate use in a build command and nowhere else.
#
# Usage:
#   scripts/devices.sh list                 human-readable report
#   scripts/devices.sh roles                ROLE=name pairs, one per line
#   scripts/devices.sh udid PRIMARY_IPAD    the UDID for one role, for piping
#   scripts/devices.sh destination PRIMARY_IPAD
#                                           an xcodebuild -destination argument
#
# Exit codes:
#   0  at least one physical device was found (and, for udid/destination,
#      the requested role was filled)
#   3  no physical device is available, or the requested role is unfilled —
#      callers must report BLOCKED, never PASSED (§177)
#   4  the device tooling itself failed
#
# Local overrides live in .keezly-devices.env, which is git-ignored. Example:
#   KEEZLY_PRIMARY_IPAD="Renes iPad"
#   KEEZLY_PRIMARY_IPHONE="Work phone"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERRIDES="${REPO_ROOT}/.keezly-devices.env"
# shellcheck disable=SC1090
[[ -f "$OVERRIDES" ]] && source "$OVERRIDES"

COMMAND="${1:-list}"
REQUESTED_ROLE="${2:-}"

TMP_JSON="$(mktemp -t keezly-devices)"
trap 'rm -f "$TMP_JSON"' EXIT

if ! xcrun devicectl list devices --json-output "$TMP_JSON" --timeout 20 >/dev/null 2>&1; then
    echo "error: 'xcrun devicectl' failed. Is Xcode installed and selected?" >&2
    echo "       xcode-select -p → $(xcode-select -p 2>/dev/null || echo 'unset')" >&2
    exit 4
fi

python3 - "$TMP_JSON" "$COMMAND" "$REQUESTED_ROLE" <<'PYTHON'
import json
import os
import sys

path, command, requested_role = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(path) as handle:
        payload = json.load(handle)
except (OSError, ValueError) as error:
    print(f"error: could not read device list: {error}", file=sys.stderr)
    sys.exit(4)

entries = payload.get("result", {}).get("devices", [])

devices = []
for entry in entries:
    hardware = entry.get("hardwareProperties", {})
    connection = entry.get("connectionProperties", {})
    properties = entry.get("deviceProperties", {})

    # 'reality' is the field that separates a real device from a simulator.
    # devicectl lists both, and a booted simulator even reports as "connected",
    # so filtering on connection state alone would be wrong.
    if hardware.get("reality") != "physical":
        continue
    if hardware.get("platform") not in ("iOS", "iPadOS"):
        continue

    devices.append({
        "name": properties.get("name") or hardware.get("marketingName") or "unknown",
        "kind": hardware.get("deviceType") or "unknown",
        "model": hardware.get("marketingName") or hardware.get("productType") or "unknown",
        "os": properties.get("osVersionNumber") or "unknown",
        "udid": hardware.get("udid") or "",
        "paired": connection.get("pairingState") == "paired",
        "tunnel": connection.get("tunnelState") or "unknown",
        "transport": connection.get("transportType") or "unknown",
        "developer_mode": properties.get("developerModeStatus") or "unknown",
    })


def usable(device):
    """Whether a build can actually be installed and run on this device."""
    return device["paired"] and device["tunnel"] != "unavailable"


def assign_roles(found):
    """Map devices onto stable roles, honouring local name overrides."""
    roles = {}
    phones = [d for d in found if d["kind"] == "iPhone"]
    pads = [d for d in found if d["kind"] == "iPad"]

    for role, pool in (("IPHONE", phones), ("IPAD", pads)):
        remaining = list(pool)
        for slot, prefix in ((f"PRIMARY_{role}", "PRIMARY"), (f"SECONDARY_{role}", "SECONDARY")):
            wanted = os.environ.get(f"KEEZLY_{slot}")
            chosen = None
            if wanted:
                chosen = next((d for d in remaining if d["name"] == wanted), None)
                if chosen is None and prefix == "PRIMARY":
                    print(
                        f"warning: KEEZLY_{slot} names '{wanted}', which is not connected",
                        file=sys.stderr,
                    )
            if chosen is None:
                # Prefer a device that is ready to run right now.
                chosen = next((d for d in remaining if usable(d)), None) or next(iter(remaining), None)
            if chosen is not None:
                remaining.remove(chosen)
                roles[slot] = chosen
    return roles


roles = assign_roles(devices)

if command == "list":
    print("KEEZLY — AVAILABLE PHYSICAL DEVICES")
    print("=" * 52)
    if not devices:
        print("none")
        print()
        print("PHYSICAL DEVICE TEST: BLOCKED")
        print("Reason:")
        print("  No physical iPhone or iPad is paired with this Mac.")
        print("Required manual action:")
        print("  Connect an iPhone or iPad by cable or pair it wirelessly in")
        print("  Xcode (Window > Devices and Simulators), unlock it, trust this")
        print("  computer, and enable Developer Mode on the device")
        print("  (Settings > Privacy & Security > Developer Mode).")
        sys.exit(3)

    reverse = {id(device): role for role, device in roles.items()}
    for device in devices:
        role = reverse.get(id(device), "—")
        print(f"{device['kind']}  {device['model']}")
        print(f"  OS         : {device['os']}")
        print(f"  Role       : {role}")
        print(f"  Paired     : {'yes' if device['paired'] else 'NO'}")
        print(f"  Connection : {device['transport']} / tunnel {device['tunnel']}")
        print(f"  Dev mode   : {device['developer_mode']}")
        print(f"  Usable     : {'yes' if usable(device) else 'NO — see KNOWN_ISSUES / manual actions'}")
        print()
    sys.exit(0)

if command == "roles":
    if not roles:
        sys.exit(3)
    for role, device in sorted(roles.items()):
        print(f"{role}={device['name']}")
    sys.exit(0)

if command in ("udid", "destination"):
    if not requested_role:
        print("error: a role is required, e.g. PRIMARY_IPAD", file=sys.stderr)
        sys.exit(4)
    device = roles.get(requested_role)
    if device is None:
        print(f"BLOCKED: no physical device fills the role {requested_role}", file=sys.stderr)
        sys.exit(3)
    if not usable(device):
        print(
            f"BLOCKED: {requested_role} is present but not usable "
            f"(paired={device['paired']}, tunnel={device['tunnel']})",
            file=sys.stderr,
        )
        sys.exit(3)
    if command == "udid":
        print(device["udid"])
    else:
        print(f"platform=iOS,id={device['udid']}")
    sys.exit(0)

print(f"error: unknown command '{command}'", file=sys.stderr)
sys.exit(4)
PYTHON
