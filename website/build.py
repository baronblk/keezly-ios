#!/usr/bin/env python3
"""Builds the Keezly website into `website/dist/`.

Static, and static all the way down: no build server, no framework, no font
CDN, no analytics, no third-party JavaScript. Upload the directory and it
works.

**The site lives at `/KEEZLY/` and never assumes it.** Every internal link and
every asset reference is *relative* to the page emitting it, so the same build
works from a subpath, from a domain root, or from a `file://` directory while
somebody checks it. Only three things are absolute, because the standards
require an absolute form: `<link rel="canonical">`, `hreflang` alternates and
the OpenGraph image. Those are built from `CANONICAL_ROOT` in one place.

    python3 website/build.py
    python3 scripts/website-check.py website/dist
"""

import html
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import content as C  # noqa: E402

DIST = HERE / "dist"
SRC = HERE / "src"
REPO = HERE.parent


# ----------------------------------------------------------------- helpers

def esc(text):
    return html.escape(str(text), quote=True)


def page_dir(locale, key):
    """Where a page lives inside dist, as a POSIX path without a leading slash."""
    return f"{C.PREFIX[locale]}{C.SLUGS[locale][key]}"


def depth_of(rel_dir):
    """How many levels up `rel_dir` sits from the site root."""
    return len([p for p in rel_dir.split("/") if p])


def rel(from_dir, to_path):
    """A link from one page directory to a site-root-relative path.

    The whole subpath question lives in this function. Nothing else in the
    build is allowed to write a leading slash.
    """
    up = "../" * depth_of(from_dir)
    link = f"{up}{to_path}"
    return link or "./"


def canonical(locale, key):
    return f"{C.CANONICAL_ROOT}{page_dir(locale, key)}"


# ---------------------------------------------------------------- template

def shell(locale, key, *, body, extra_head=""):
    t = C.T[locale]
    here = page_dir(locale, key)
    css = rel(here, "assets/keezly.css")
    icon = rel(here, "assets/keezly-icon.png")

    nav_items = []
    for nav_key in C.NAV_ORDER:
        href = rel(here, page_dir(locale, nav_key))
        current = ' aria-current="page"' if nav_key == key else ""
        nav_items.append(f'<a href="{esc(href)}"{current}>{esc(t["nav"][nav_key])}</a>')

    langs = []
    for other in C.LOCALES:
        href = rel(here, page_dir(other, key))
        current = ' aria-current="true"' if other == locale else ""
        label = {"de": "DE", "nl": "NL", "en": "EN"}[other]
        name = {"de": "Deutsch", "nl": "Nederlands", "en": "English"}[other]
        langs.append(
            f'<a href="{esc(href)}" hreflang="{C.HREFLANG[other]}" '
            f'lang="{other}" title="{esc(name)}"{current}>{label}</a>'
        )

    alternates = "\n  ".join(
        f'<link rel="alternate" hreflang="{C.HREFLANG[o]}" href="{esc(canonical(o, key))}">'
        for o in C.LOCALES
    )

    meta = t[key]["meta"]
    title = t[key]["title"]

    foot_links = "\n      ".join(
        f'<li><a href="{esc(rel(here, page_dir(locale, k)))}">{esc(t["nav"][k])}</a></li>'
        for k in C.NAV_ORDER
    )

    return f"""<!doctype html>
<html lang="{t['lang']}" dir="{t['dir']}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)}</title>
  <meta name="description" content="{esc(meta)}">
  <link rel="canonical" href="{esc(canonical(locale, key))}">
  {alternates}
  <link rel="alternate" hreflang="x-default" href="{esc(canonical('en', key))}">
  <meta name="theme-color" media="(prefers-color-scheme: light)" content="#e8d5b7">
  <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#16130f">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Keezly">
  <meta property="og:locale" content="{C.HREFLANG[locale].replace('-', '_')}">
  <meta property="og:title" content="{esc(title)}">
  <meta property="og:description" content="{esc(meta)}">
  <meta property="og:url" content="{esc(canonical(locale, key))}">
  <meta property="og:image" content="{esc(C.CANONICAL_ROOT)}assets/keezly-og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" sizes="180x180" href="{esc(icon)}">
  <link rel="apple-touch-icon" href="{esc(icon)}">
  <link rel="stylesheet" href="{esc(css)}">
{extra_head}</head>
<body>
<a class="skip" href="#main">{esc(t['skip'])}</a>

<header class="site-head">
  <div class="wrap">
    <a class="brand" href="{esc(rel(here, page_dir(locale, 'home')))}">
      <img src="{esc(icon)}" alt="" width="34" height="34">
      <span>Keezly</span>
    </a>
    <nav class="site-nav" aria-label="{esc(t['nav']['home'])}">
      {" ".join(nav_items)}
    </nav>
    <div class="langs">{"".join(langs)}</div>
  </div>
</header>

<main id="main">
{body}
</main>

<footer class="site-foot">
  <div class="wrap">
    <ul class="foot-links">
      {foot_links}
    </ul>
    <p class="copy">{esc(C.COPYRIGHT)} · {esc(t['foot_note'])}</p>
  </div>
</footer>
</body>
</html>
"""


# ------------------------------------------------------------------- pages

def home(locale, shots):
    t = C.T[locale]
    h = t["home"]
    here = page_dir(locale, "home")

    badges = "".join(f"<li>{esc(b)}</li>" for b in h["badges"])
    cards = "\n".join(
        f'<li class="card"><h3>{esc(title)}</h3><p>{esc(text)}</p></li>'
        for title, text in h["features"]
    )

    hero_img = ""
    if shots:
        src = rel(here, f"assets/shots/{shots[0]['file']}")
        hero_img = (
            f'<figure class="hero-shot">'
            f'<img src="{esc(src)}" alt="{esc(shots[0]["alt"])}" loading="eager" '
            f'width="{shots[0]["w"]}" height="{shots[0]["h"]}">'
            f"</figure>"
        )

    gallery = ""
    if len(shots) > 1:
        figures = "\n".join(
            f'<figure><img src="{esc(rel(here, "assets/shots/" + s["file"]))}" '
            f'alt="{esc(s["alt"])}" loading="lazy" width="{s["w"]}" height="{s["h"]}">'
            f"<figcaption>{esc(s['caption'])}</figcaption></figure>"
            for s in shots[1:]
        )
        gallery = f"""
<section aria-labelledby="shots-h">
  <div class="wrap">
    <h2 id="shots-h">{esc(h['shots_h'])}</h2>
    <div class="shots">
{figures}
    </div>
  </div>
</section>"""

    privacy_href = rel(here, page_dir(locale, "privacy"))

    return f"""
<section class="hero">
  <div class="wrap hero-grid">
    <div>
      <h1>{esc(h['h1'])}</h1>
      <p class="lede"><strong>{esc(h['tagline'])}</strong></p>
      <p class="lede">{esc(h['lede'])}</p>
      <ul class="badges">{badges}</ul>
    </div>
    {hero_img}
  </div>
</section>

<section aria-labelledby="features-h">
  <div class="wrap">
    <h2 id="features-h">{esc(h['features_h'])}</h2>
    <ul class="cards">
{cards}
    </ul>
  </div>
</section>
{gallery}

<section aria-labelledby="privacy-h">
  <div class="wrap prose">
    <h2 id="privacy-h">{esc(h['privacy_h'])}</h2>
    <p>{esc(h['privacy_p'])}</p>
    <p><a href="{esc(privacy_href)}">{esc(h['privacy_link'])}</a></p>
  </div>
</section>
"""


def support(locale):
    t = C.T[locale]
    s = t["support"]
    faq = "\n".join(
        f"<h3>{esc(q)}</h3><p>{esc(a)}</p>" for q, a in s["faq"]
    )
    return f"""
<section>
  <div class="wrap prose">
    <h1>{esc(s['h1'])}</h1>
    <p>{esc(s['intro'])}</p>

    <h2>{esc(s['contact_h'])}</h2>
    <dl class="facts">
      <dt>{esc(s['email_label'])}</dt>
      <dd><a href="mailto:{esc(C.SUPPORT_EMAIL)}">{esc(C.SUPPORT_EMAIL)}</a></dd>
      <dt>{esc(s['hub_label'])}</dt>
      <dd><a href="{esc(C.SUPPORT_HUB)}">{esc(C.SUPPORT_HUB)}</a></dd>
    </dl>

    <div class="note"><p>{esc(s['response_note'])}</p></div>

    <h2>{esc(s['faq_h'])}</h2>
    {faq}
  </div>
</section>
"""


def privacy(locale):
    t = C.T[locale]
    p = t["privacy"]
    body = PRIVACY_BODY[locale]
    return f"""
<section>
  <div class="wrap prose">
    <h1>{esc(p['h1'])}</h1>
    <p class="lede"><strong>{esc(p['lede'])}</strong></p>
{body}
  </div>
</section>
"""


def imprint(locale):
    t = C.T[locale]
    i = t["imprint"]
    m = C.IMPRESSUM
    return f"""
<section>
  <div class="wrap prose">
    <h1>{esc(i['h1'])}</h1>
    <p>{esc(i['intro'])}</p>

    <h2>{esc(i['provider_h'])}</h2>
    <address>
      {esc(m['name'])}<br>
      {esc(m['street'])}<br>
      {esc(m['postcode'])} {esc(m['city'])}<br>
      {esc(m['country'])}
    </address>

    <h2>{esc(i['contact_h'])}</h2>
    <dl class="facts">
      <dt>{esc(i['email_label'])}</dt>
      <dd><a href="mailto:{esc(m['email'])}">{esc(m['email'])}</a></dd>
      <dt>{esc(i['phone_label'])}</dt>
      <dd>{esc(m['phone'])}</dd>
    </dl>

    <h2>{esc(i['vat_h'])}</h2>
    <p>{esc(i['vat_p'])}</p>

    <h2>{esc(i['dispute_h'])}</h2>
    <p>{esc(i['dispute_p'])}</p>
  </div>
</section>
"""


def a11y(locale):
    t = C.T[locale]
    a = t["a11y"]
    return f"""
<section>
  <div class="wrap prose">
    <h1>{esc(a['h1'])}</h1>
    <p class="lede"><strong>{esc(a['lede'])}</strong></p>
{A11Y_BODY[locale]}
  </div>
</section>
"""


# The long-form legal and accessibility prose. Kept as literals rather than
# assembled from fragments: a privacy statement has to read as one document to
# a person, not as a template that happens to render.
PRIVACY_BODY = {}
A11Y_BODY = {}


def load_prose():
    mod = __import__("prose")
    PRIVACY_BODY.update(mod.PRIVACY_BODY)
    A11Y_BODY.update(mod.A11Y_BODY)


# ------------------------------------------------------------------- shots

def collect_shots():
    """Per-locale screenshots, taken from the verified capture set if present."""
    src = REPO / "artifacts" / "screenshots"
    picks = {
        "iphone": ["phone-mid-match-portrait", "phone-four-players-portrait",
                   "phone-six-players-portrait"],
        "ipad": ["four-players-landscape", "six-players-landscape", "menu"],
    }
    alt = {
        "de": {"phone-mid-match-portrait": "Keezly auf dem iPhone, mitten in einer Partie",
               "phone-four-players-portrait": "Vier Spieler auf dem iPhone",
               "phone-six-players-portrait": "Sechs Spieler auf dem iPhone",
               "four-players-landscape": "Vier Spieler auf dem iPad im Querformat",
               "six-players-landscape": "Sechs Spieler auf dem iPad",
               "menu": "Das Startmenü von Keezly"},
        "nl": {"phone-mid-match-portrait": "Keezly op de iPhone, midden in een partij",
               "phone-four-players-portrait": "Vier spelers op de iPhone",
               "phone-six-players-portrait": "Zes spelers op de iPhone",
               "four-players-landscape": "Vier spelers op de iPad, liggend",
               "six-players-landscape": "Zes spelers op de iPad",
               "menu": "Het startmenu van Keezly"},
        "en": {"phone-mid-match-portrait": "Keezly on iPhone, mid-match",
               "phone-four-players-portrait": "Four players on iPhone",
               "phone-six-players-portrait": "Six players on iPhone",
               "four-players-landscape": "Four players on iPad, landscape",
               "six-players-landscape": "Six players on iPad",
               "menu": "The Keezly start menu"},
    }
    out = {loc: [] for loc in C.LOCALES}
    if not src.exists():
        return out

    try:
        from PIL import Image
    except ImportError:
        return out

    shot_dir = DIST / "assets" / "shots"
    shot_dir.mkdir(parents=True, exist_ok=True)

    for loc in C.LOCALES:
        for device in ("iphone", "ipad"):
            folder = src / f"{device}-{loc}"
            if not folder.exists():
                continue
            for name in picks[device]:
                origin = folder / f"{name}.png"
                if not origin.exists():
                    continue
                target_name = f"{loc}-{device}-{name}.jpg"
                with Image.open(origin) as im:
                    im = im.convert("RGB")
                    # Downscaled for the web. The store set keeps full size;
                    # a landing page does not need 2752 pixels of anything.
                    im.thumbnail((1000, 1000), Image.LANCZOS)
                    im.save(shot_dir / target_name, "JPEG", quality=82, optimize=True)
                    w, h = im.size
                out[loc].append({
                    "file": target_name, "w": w, "h": h,
                    "alt": alt[loc][name], "caption": alt[loc][name],
                })
    return out


# ------------------------------------------------------------------- build

def build():
    load_prose()

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)

    (DIST / "assets").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC / "assets" / "keezly.css", DIST / "assets" / "keezly.css")

    icon = REPO / "App/Keezly/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    if icon.exists():
        try:
            from PIL import Image
            with Image.open(icon) as im:
                im.convert("RGB").resize((180, 180), Image.LANCZOS).save(
                    DIST / "assets" / "keezly-icon.png")
                og = Image.new("RGB", (1200, 630), (216, 190, 150))
                art = im.convert("RGB").resize((420, 420), Image.LANCZOS)
                og.paste(art, (390, 105))
                og.save(DIST / "assets" / "keezly-og.png")
        except ImportError:
            shutil.copy2(icon, DIST / "assets" / "keezly-icon.png")

    shots = collect_shots()

    written = []
    builders = {"home": lambda loc: home(loc, shots[loc]),
                "support": support, "privacy": privacy,
                "imprint": imprint, "a11y": a11y}

    for loc in C.LOCALES:
        for key, fn in builders.items():
            out_dir = DIST / page_dir(loc, key)
            out_dir.mkdir(parents=True, exist_ok=True)
            page = shell(loc, key, body=fn(loc))
            (out_dir / "index.html").write_text(page, encoding="utf-8")
            written.append(str((out_dir / "index.html").relative_to(DIST)))

    # robots.txt and sitemap.xml, both absolute by specification.
    (DIST / "robots.txt").write_text(
        "User-agent: *\nAllow: /\n\n"
        f"Sitemap: {C.CANONICAL_ROOT}sitemap.xml\n", encoding="utf-8")

    urls = "\n".join(
        "  <url>\n"
        f"    <loc>{canonical(loc, key)}</loc>\n"
        + "".join(
            f'    <xhtml:link rel="alternate" hreflang="{C.HREFLANG[o]}" '
            f'href="{canonical(o, key)}"/>\n' for o in C.LOCALES)
        + "  </url>"
        for key in C.NAV_ORDER for loc in C.LOCALES
    )
    (DIST / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
        '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        f"{urls}\n</urlset>\n", encoding="utf-8")

    print(f"built {len(written)} pages into {DIST}")
    for loc in C.LOCALES:
        print(f"  {loc}: {len(shots[loc])} screenshot(s)")
    return 0


if __name__ == "__main__":
    sys.exit(build())
