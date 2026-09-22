# Deploying the Keezly website

**Status: GENERATED / DEPLOYABLE.** Nothing here has been uploaded. The site is
not live until you put it somewhere, and this document does not claim it is.

---

## What to upload

Everything inside `website/dist/`, preserving the directory structure, to:

```
https://gcng.de/KEEZLY/
```

so that `website/dist/index.html` is served as `https://gcng.de/KEEZLY/`.

A zip of exactly that directory is built alongside it:

```
website/website-keezly-1.0.0.zip
```

## Rebuilding

```bash
python3 website/build.py
python3 scripts/website-check.py website/dist
```

The build is deterministic and wipes `dist/` first, so it never leaves an old
page behind that nothing links to any more.

---

## The subpath is the whole risk

The site is served from `/KEEZLY/` and **nothing in it assumes that**. Every
internal link and every asset reference is relative to the page emitting it, so
the same build works from a subpath, from a domain root, or from a `file://`
directory while somebody reviews it.

Three things are absolute, because the standards require it: `rel="canonical"`,
the `hreflang` alternates, and the OpenGraph image. All three are built from one
constant, `CANONICAL_ROOT` in `website/content.py`. **If the site ever moves,
change that one line and rebuild** — do not edit HTML.

`scripts/website-check.py` fails the build if any reference starts with `/`,
because that is the fault that works perfectly in a local preview and 404s the
moment it is deployed.

---

## File permissions

Directories `755`, files `644`, owned by whatever user your web server reads
as. Nothing needs to be executable and nothing needs to be writable by the
server: there is no database, no server application, no form handler and no
upload path.

```bash
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
```

---

## Before you upload

Serve the directory locally and click through it. The built-in Python server is
enough, but it must be rooted so that `/KEEZLY/` exists, or you will be testing
a layout the live site will not have:

```bash
mkdir -p /tmp/keezly-preview
cp -R website/dist /tmp/keezly-preview/KEEZLY
cd /tmp/keezly-preview && python3 -m http.server 8080
# then open http://localhost:8080/KEEZLY/
```

Check by hand, because no script can:

- the German, Dutch and English pages each read naturally to somebody who
  speaks that language — the Dutch especially, which is the primary locale
- the screenshots show the app you want shown
- the Impressum matches your current legal details

---

## After you upload

```bash
for u in "" nl/ en/ support/ nl/support/ en/support/ \
         datenschutz/ nl/privacy/ en/privacy/ \
         impressum/ nl/colofon/ en/imprint/ \
         barrierefreiheit/ nl/toegankelijkheid/ en/accessibility/ \
         robots.txt sitemap.xml assets/keezly.css; do
  printf '%s  %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "https://gcng.de/KEEZLY/$u")" "/$u"
done
```

Every line must read `200`. Then check in a browser that:

- HTTPS has no mixed-content warning
- the page is usable at phone width
- tabbing from the top reaches the skip link first
- the language switcher moves between the same page in each language, not to
  the home page

Only then is it **LIVE VERIFIED**, and only then should the App Store URLs be
pointed at it.

---

## What is deliberately not here

- No analytics, no tag manager, no cookie banner — there is nothing to consent
  to, and a banner asking permission to do nothing is worse than no banner.
- No web fonts from anybody else's server. The site uses the reader's system
  font stack, which is also what makes it look native on an Apple device.
- No JavaScript at all. `scripts/website-check.py` fails the build if any
  appears.
- No `.htaccess`, no redirects, no server configuration. If you need a redirect
  from an old path, that is a server matter and belongs with your server
  config, not in this directory.
