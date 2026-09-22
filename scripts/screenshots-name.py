#!/usr/bin/env python3
"""Gives exported screenshot attachments their real names.

`xcresulttool export attachments` writes one file per attachment named by its
payload id, and records what each one actually is in `manifest.json`. A
directory of thirty-two-character hex names is not a screenshot set anybody can
review, let alone upload, so this renames them from the manifest.

Idempotent: running it twice leaves the same names.
"""

import json
import re
import sys
from pathlib import Path


def slug(name):
    """The capture's own name, without what the exporter added to it.

    `suggestedHumanReadableName` is the attachment's name with an index and a
    UUID appended and `.png` on the end — "menu_0_E8FC6A10-….png". All three
    come off: the index and the id say nothing a reader wants, and leaving the
    extension on gave every file a name ending `.png.png`.
    """
    stem = re.sub(r"\.png$", "", name, flags=re.IGNORECASE)
    stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-")
    return cleaned or "capture"


def main():
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else "build/screenshots")
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        print(f"No manifest in {directory} — nothing was exported.", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text())
    # The schema nests attachments under each test. Walk it rather than
    # assuming a shape: a version bump that moves them would otherwise rename
    # nothing and report success.
    renamed = 0
    entries = manifest if isinstance(manifest, list) else manifest.get("tests", [])
    for test in entries:
        for attachment in test.get("attachments", []):
            exported = attachment.get("exportedFileName")
            suggested = attachment.get("suggestedHumanReadableName") or attachment.get("name")
            if not exported or not suggested:
                continue
            source = directory / exported
            if not source.exists():
                continue
            target = directory / f"{slug(suggested)}.png"
            if source == target:
                continue
            source.replace(target)
            renamed += 1

    print(f"  named {renamed} capture(s) in {directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
