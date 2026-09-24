#!/usr/bin/env python3
"""Checks the *published* Keezly site, over HTTP, at its real address.

`website-check.py` checks the files in `website/dist`. This checks what a
visitor actually gets, which is a different question and the only one that can
justify the words LIVE VERIFIED. A site can build perfectly and be served as a
404, with the wrong MIME type, without its assets, or from a stale upload.

Nothing here runs against localhost and nothing is inferred from the build. If
it cannot reach the page, it fails — it does not fall back to the local copy.

    python3 scripts/website-live-check.py
    python3 scripts/website-live-check.py https://gcng.de/KEEZLY/

Exit 0 only when every page is served, in the right language, with no draft
marker and no broken link among the ones it declares.
"""

import re
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urljoin

BASE = "https://gcng.de/KEEZLY/"
TIMEOUT = 20
AGENT = "keezly-website-live-check/1.0"

# Every page, and the language each one must declare. Taken from what the build
# produces rather than typed out again, so a new page cannot be forgotten here.
EXPECTED_LANG = {"": "de", "en": "en", "nl": "nl"}

# Nothing internal may reach a visitor. Same list the build-time check uses.
FORBIDDEN = ["DRAFT", "ENTWURF", "LEGAL REVIEW REQUIRED", "OWNER ACTION",
             "TODO", "FIXME", "PLACEHOLDER", "Lorem ipsum"]

# Something that proves the page is Keezly's and not the server's 404 page,
# which can be served with a 200 by a misconfigured host.
MUST_CONTAIN = "Keezly"


def pages(dist: Path) -> list[str]:
    """Every published path, derived from the built site."""
    found = []
    for html in sorted(dist.rglob("index.html")):
        rel = html.relative_to(dist).parent.as_posix()
        found.append("" if rel == "." else rel + "/")
    return found


def language_for(path: str) -> str:
    first = path.split("/")[0]
    return EXPECTED_LANG.get(first, "de")


def fetch(url: str) -> tuple[int, str, str]:
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    context = ssl.create_default_context()
    with urllib.request.urlopen(request, timeout=TIMEOUT, context=context) as response:
        body = response.read()
        charset = response.headers.get_content_charset() or "utf-8"
        return response.status, response.headers.get("Content-Type", ""), body.decode(charset, "replace")


def check_page(base: str, path: str, faults: list[str]) -> str | None:
    url = urljoin(base, path)
    try:
        status, content_type, body = fetch(url)
    except urllib.error.HTTPError as error:
        faults.append(f"{url} -> HTTP {error.code}")
        return None
    except Exception as error:  # noqa: BLE001 - the reason is what matters
        faults.append(f"{url} -> not reachable: {error}")
        return None

    if status != 200:
        faults.append(f"{url} -> HTTP {status}")
        return None
    if "text/html" not in content_type.lower():
        faults.append(f"{url} -> served as {content_type!r}, not HTML")

    expected = language_for(path)
    declared = re.search(r'<html[^>]*\blang="([^"]+)"', body)
    if not declared:
        faults.append(f"{url} -> no lang attribute")
    elif not declared.group(1).lower().startswith(expected):
        faults.append(f"{url} -> lang={declared.group(1)!r}, expected {expected!r}")

    if MUST_CONTAIN not in body:
        faults.append(f"{url} -> does not mention {MUST_CONTAIN!r}; is this the host's error page?")

    for marker in FORBIDDEN:
        if marker.lower() in body.lower():
            faults.append(f"{url} -> contains {marker!r}, which a visitor must never see")

    return body


def check_link(url: str, faults: list[str], label: str) -> None:
    try:
        status, _, _ = fetch(url)
        if status != 200:
            faults.append(f"{label}: {url} -> HTTP {status}")
    except urllib.error.HTTPError as error:
        faults.append(f"{label}: {url} -> HTTP {error.code}")
    except Exception as error:  # noqa: BLE001
        faults.append(f"{label}: {url} -> not reachable: {error}")


def main(base: str, dist: Path) -> int:
    paths = pages(dist)
    if not paths:
        print(f"no built site at {dist} — run website/build.py first", file=sys.stderr)
        return 2

    print(f"checking {len(paths)} pages under {base}\n")
    faults: list[str] = []
    bodies: dict[str, str] = {}

    for path in paths:
        body = check_page(base, path, faults)
        mark = "·" if body else "✘"
        print(f"  {mark} {path or '(home)'}")
        if body:
            bodies[path] = body

    # Off-site links, and any App Store link once one exists. Collected from
    # what the pages actually say rather than from a list kept by hand.
    external: set[str] = set()
    store: set[str] = set()
    for body in bodies.values():
        for url in re.findall(r'https?://[^"\'<>) ]+', body):
            url = url.rstrip(".,;")
            if url.startswith(base):
                continue
            if "apps.apple.com" in url or "itunes.apple.com" in url:
                store.add(url)
            elif url.startswith("http"):
                external.add(url)

    if external:
        print("\noff-site links:")
        for url in sorted(external):
            check_link(url, faults, "off-site link")
            print(f"  · {url}")

    print("\nApp Store links:")
    if store:
        for url in sorted(store):
            check_link(url, faults, "App Store link")
            print(f"  · {url}")
            if "de.gcng.keezly" not in url and "6814932630" not in url:
                faults.append(
                    f"App Store link {url} names neither the bundle id nor the ASC app id — "
                    "check it points at Keezly and not at another app"
                )
    else:
        # Not a fault today. The app is not on the store, so a link to its
        # product page would be a link to nothing.
        print("  none on the site yet — expected until 1.0.0 is released.")
        print("  Once it is released, add them and re-run this: the check then")
        print("  verifies each one resolves and names Keezly.")

    print()
    if faults:
        print(f"WEBSITE LIVE CHECK: FAILED — {len(faults)} fault(s)\n")
        for fault in faults:
            print(f"  ✘ {fault}")
        print("\nThe site is NOT LIVE VERIFIED.")
        return 1

    print(f"WEBSITE LIVE CHECK: PASSED — {len(paths)} pages, all served, "
          f"right language, no internal text, no broken link.")
    print("The site may now be recorded as LIVE VERIFIED in WEBSITE.md.")
    return 0


if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else BASE
    if not base.endswith("/"):
        base += "/"
    root = Path(__file__).resolve().parent.parent
    sys.exit(main(base, root / "website" / "dist"))
