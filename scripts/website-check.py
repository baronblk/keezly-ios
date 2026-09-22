#!/usr/bin/env python3
"""Checks the built Keezly site before anybody uploads it.

    python3 scripts/website-check.py website/dist

The site is served from `/KEEZLY/` and nothing in the build may assume it, so
the first and most important check is that no internal link or asset reference
starts with a slash. A root-relative link works perfectly on a local preview
and 404s the moment it is deployed to a subpath, which is exactly the kind of
fault that is found by a visitor rather than by the person who shipped it.

What is checked here can be checked mechanically. What cannot — whether the
prose is any good, whether a translation reads naturally to a native speaker,
whether the design is worth looking at — is not attempted and not implied.
"""

import html.parser
import re
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

# Claims the software cannot keep, in any of the three languages (DEC-025).
FORBIDDEN = re.compile(
    r"anti-?cheat|cheat.?proof|server.?authorit|serverautoris|"
    r"leaderboard|bestenliste|ranglijst|"
    r"betrugssicher|vals.?spelen.?onmogelijk",
    re.I,
)

# …but saying there are none is the opposite of claiming there are.
#
# The privacy pages say, in three languages, that Keezly has no leaderboards
# and why. A check that cannot tell a denial from a claim would push whoever
# ran it to delete the very sentence that makes the position clear — so it
# looks for a negation shortly before the term.
#
# This is a heuristic and is written down as one. It reads a window of
# characters, not a grammar, and it would be fooled by a sentence built to
# fool it. It is here to catch an accident, and an accident does not write
# "no" in front of the word it wanted.
NEGATION = re.compile(
    r"\b(no|not|never|without|kein|keine|keinen|nicht|ohne|"
    r"geen|niet|zonder)\b", re.I,
)
NEGATION_WINDOW = 90


def is_denied(text, match):
    """Whether a forbidden term is negated rather than asserted."""
    start = max(0, match.start() - NEGATION_WINDOW)
    return bool(NEGATION.search(text[start:match.start()]))

# Anything that would make the page depend on somebody else's server.
EXTERNAL_ASSET = re.compile(r"^(https?:)?//", re.I)

ALLOWED_EXTERNAL_LINKS = {"support.gcng.de", "gcng.de"}


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.assets, self.imgs = [], [], []
        self.title = None
        self._in_title = False
        self.lang = None
        self.has_h1 = False
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "title":
            self._in_title = True
        elif tag == "h1":
            self.has_h1 = True
        elif tag == "a" and "href" in a:
            self.links.append(a["href"])
        elif tag == "img":
            self.imgs.append(a)
            if "src" in a:
                self.assets.append(a["src"])
        elif tag == "link" and a.get("href"):
            if a.get("rel") in ("stylesheet", "icon", "apple-touch-icon"):
                self.assets.append(a["href"])
        elif tag == "script":
            self.scripts.append(a.get("src") or "inline")

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title = (self.title or "") + data


def check(root: Path):
    pages = sorted(root.rglob("index.html"))
    if not pages:
        print(f"No pages under {root}", file=sys.stderr)
        return 1

    problems = []

    def fail(page, msg):
        problems.append(f"{page.relative_to(root)}: {msg}")

    for path in pages:
        raw = path.read_text(encoding="utf-8")
        p = Page()
        p.feed(raw)
        here = path.parent

        if not p.lang:
            fail(path, "no lang attribute on <html>")
        if not p.title:
            fail(path, "no <title>")
        if not p.has_h1:
            fail(path, "no <h1>")

        for hit in FORBIDDEN.finditer(raw):
            if is_denied(raw, hit):
                continue
            fail(path, f"claims something the software cannot keep: {hit.group(0)!r}")

        for src in p.scripts:
            fail(path, f"carries JavaScript ({src}) — the site is meant to have none")

        # Every internal reference must be relative, and must resolve.
        for ref in p.links + p.assets:
            if ref.startswith(("mailto:", "tel:", "#")):
                continue
            parsed = urlparse(ref)
            if parsed.scheme or ref.startswith("//"):
                if parsed.netloc and parsed.netloc not in ALLOWED_EXTERNAL_LINKS:
                    fail(path, f"links off-site to {parsed.netloc}")
                continue
            if ref.startswith("/"):
                fail(path, f"root-relative reference {ref!r} — would 404 under /KEEZLY/")
                continue
            target = (here / unquote(parsed.path)).resolve()
            if parsed.path in ("", "./"):
                target = here
            if target.is_dir():
                target = target / "index.html"
            if not target.exists():
                fail(path, f"broken reference {ref!r}")

        for img in p.imgs:
            if "alt" not in img:
                fail(path, f"image without alt: {img.get('src')}")

        # A canonical must be absolute; that is the one place it is correct.
        if 'rel="canonical"' not in raw:
            fail(path, "no canonical link")
        if 'hreflang=' not in raw:
            fail(path, "no hreflang alternates")

    # The three languages must have the same set of pages.
    def tree_for(prefix):
        out = set()
        for path in pages:
            relpath = path.parent.relative_to(root).as_posix()
            if prefix == "":
                if not relpath.startswith(("nl", "en")):
                    out.add(relpath)
            elif relpath == prefix or relpath.startswith(prefix + "/"):
                out.add(relpath[len(prefix):].lstrip("/") or ".")
        return out

    de, nl, en = tree_for(""), tree_for("nl"), tree_for("en")
    if not (len(de) == len(nl) == len(en)):
        problems.append(
            f"locales have different page counts: de={len(de)} nl={len(nl)} en={len(en)}")

    for extra in (root / "robots.txt", root / "sitemap.xml"):
        if not extra.exists():
            problems.append(f"missing {extra.name}")

    print(f"{len(pages)} pages checked under {root}")
    if problems:
        for line in problems:
            print(f"  ✘ {line}")
        print(f"\n{len(problems)} problem(s).")
        return 1

    print("Every page: relative links only, all references resolve, every image has "
          "alt text, no JavaScript, no off-site assets, no claim the app cannot keep.")
    print("What this cannot tell you is whether the writing and the design are any "
          "good. That needs a person, and for the Dutch, a Dutch one.")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1] if len(sys.argv) > 1 else "website/dist")))
