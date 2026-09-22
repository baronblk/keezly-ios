# -*- coding: utf-8 -*-
"""Everything the Keezly site says, in three languages.

Kept apart from the templating so that a claim can be checked by reading it
rather than by reading HTML. Two rules govern what may go in here:

1. **Only what the app does.** Keezly 1.0.0 is a local game with an optional
   Game Center turn-based mode. There is no account, no advertising, no
   tracking and no server of ours. Nothing here may say otherwise.
2. **Nothing about anti-cheat, leaderboards or server-authorised play.** There
   is no server that could make any of it true (DEC-025), and a fairness claim
   the software cannot keep is worse than no claim at all.

`scripts/website-check.py` enforces both against the built HTML.

The legal details are transcribed from the owner's own published pages at
support.gcng.de and are not invented here. Anything those pages do not state
is marked for review rather than filled in.
"""

# Verified 2026-09-22 from https://support.gcng.de/legal/impressum.html
IMPRESSUM = {
    "name": "Rene Suess",
    "role": "Freiberufler",
    "street": "Barbarossastraße 91",
    "postcode": "09112",
    "city": "Chemnitz",
    "country": "Deutschland",
    "email": "support@gcng.de",
    "phone": "+49 (0) 176 222 92 818",
    "responsible": "Rene Suess",
}

SUPPORT_EMAIL = "support@gcng.de"
SUPPORT_HUB = "https://support.gcng.de/"
BASE = "/KEEZLY/"
CANONICAL_ROOT = "https://gcng.de/KEEZLY/"
COPYRIGHT = "© 2026 Rene Suess"

LOCALES = ["de", "nl", "en"]
HREFLANG = {"de": "de-DE", "nl": "nl-NL", "en": "en"}
# German lives at the root; the other two get a prefix.
PREFIX = {"de": "", "nl": "nl/", "en": "en/"}

# Page slugs differ per language on purpose: a Dutch reader should not have to
# read a German URL. The keys are stable, the paths are not.
SLUGS = {
    "de": {"home": "", "support": "support/", "privacy": "datenschutz/",
           "imprint": "impressum/", "a11y": "barrierefreiheit/"},
    "nl": {"home": "", "support": "support/", "privacy": "privacy/",
           "imprint": "colofon/", "a11y": "toegankelijkheid/"},
    "en": {"home": "", "support": "support/", "privacy": "privacy/",
           "imprint": "imprint/", "a11y": "accessibility/"},
}

NAV_ORDER = ["home", "support", "a11y", "privacy", "imprint"]

T = {}

# --------------------------------------------------------------------- German
T["de"] = {
    "lang": "de",
    "dir": "ltr",
    "site_name": "Keezly",
    "nav": {"home": "Start", "support": "Hilfe", "privacy": "Datenschutz",
            "imprint": "Impressum", "a11y": "Barrierefreiheit"},
    "skip": "Zum Inhalt springen",
    "home": {
        "title": "Keezly: Keezenspel — das niederländische Brettspiel für iPhone und iPad",
        "meta": "Keezen für zwei bis sechs Spieler, auf einem Gerät oder gegen den "
                "Computer. Kein Konto, keine Werbung, kein Tracking.",
        "h1": "Keezly",
        "tagline": "Das niederländische Brettspiel, für zwei bis sechs Spieler.",
        "lede": "Vier Figuren ums Brett, die anderen hinauswerfen, alle vier heil nach "
                "Hause bringen. Auf einem Gerät weiterreichen oder gegen drei "
                "Computerstärken spielen — offline, ohne Konto, ohne Werbung.",
        "badges": ["iPhone und iPad", "2–6 Spieler", "Deutsch · Nederlands · English",
                   "Keine Werbung", "Kein Tracking"],
        "features_h": "Was Keezly kann",
        "features": [
            ("Zwei bis sechs Spieler",
             "Im Team oder jeder für sich. Zwei, drei, vier, fünf oder sechs am Tisch — "
             "das Brett passt sich jeder Tischgröße an, die Regeln bleiben dieselben."),
            ("Weiterreichen, richtig gemacht",
             "Das Gerät wandert um den Tisch. Wenn Sie an der Reihe sind, wartet der "
             "Bildschirm, bis Sie bestätigen, dass Sie ihn halten — so sieht niemand "
             "eine fremde Hand."),
            ("Drei Computergegner",
             "Leicht spielt regelkonform und gut gelaunt. Mittel passt auf die eigenen "
             "Figuren auf. Schwer liest die Stellung und wirft Sie hinaus. An einem "
             "Tisch beliebig mischbar."),
            ("Ihre Hausregeln",
             "Was der König darf, ob eine Extrarunde erlaubt ist, ob eigene Figuren "
             "blockieren, ob der Partner hinausgeworfen werden darf, ob das Haus streng "
             "von hinten gefüllt wird — jede Regel ist ein Schalter."),
            ("In zehn Minuten gelernt",
             "Ein Tutorial, das durch Spielen erklärt statt durch Lesen, und ein "
             "Regelbuch, das sich mitten im Zug öffnen lässt."),
            ("Noch einmal ansehen",
             "Jede beendete Partie wird gespeichert und lässt sich Zug für Zug "
             "wiedergeben. Die Statistik wird aus diesen Partien berechnet."),
            ("Game Center",
             "Optional und freundschaftlich: eine rundenbasierte Partie über Apples "
             "Game Center, wenn Sie mögen. Ohne Anmeldung spielt Keezly genauso."),
            ("Barrierefrei bedienbar",
             "Vollständige VoiceOver-Unterstützung, dynamische Schrift, eine Liste "
             "aller erlaubten Züge und eine Bedienung, die nicht von Farbe abhängt."),
        ],
        "shots_h": "Aus dem Spiel",
        "privacy_h": "Was Keezly nicht tut",
        "privacy_p": "Kein Konto. Keine Werbung. Keine Käufe. Kein Tracking, keine "
                     "Analyse, keine Daten, die das Gerät verlassen. Keezly funktioniert "
                     "im Flugmodus, weil es nichts gibt, womit es sich verbinden müsste.",
        "privacy_link": "Ausführlich in der Datenschutzerklärung",
    },
    "support": {
        "title": "Hilfe zu Keezly",
        "meta": "Kontakt und Hilfe zu Keezly: Keezenspel.",
        "h1": "Hilfe",
        "intro": "Fragen, Fehlerberichte und Vorschläge gehen an dieselbe Adresse.",
        "contact_h": "Kontakt",
        "email_label": "E-Mail",
        "hub_label": "Zentrale Support-Seite",
        "faq_h": "Häufige Fragen",
        "faq": [
            ("Brauche ich eine Internetverbindung?",
             "Nein. Alle lokalen Modi — gegen den Computer und das Weiterreichen am "
             "Tisch — funktionieren vollständig offline. Nur eine Game-Center-Partie "
             "braucht eine Verbindung."),
            ("Brauche ich ein Konto?",
             "Nein. Keezly hat keine eigene Anmeldung. Game Center ist optional und "
             "wird von Apple bereitgestellt."),
            ("Wo werden meine Partien gespeichert?",
             "Auf dem Gerät, im Bereich der App. Sie verschwinden, wenn die App "
             "gelöscht wird."),
            ("Kann ich die Regeln anpassen?",
             "Ja. Die Hausregeln, über die Familien streiten, sind einzeln "
             "umschaltbar, dazu gibt es zwei fertige Voreinstellungen."),
        ],
        "response_note": "Diese Seite verspricht keine Reaktionszeit. Zusagen zur "
                         "Bearbeitungsdauer gibt es für Keezly nicht.",
    },
    "privacy": {
        "title": "Datenschutz — Keezly",
        "meta": "Datenschutzerklärung für die Keezly-App und diese Website.",
        "h1": "Datenschutz",
        "lede": "Keezly erhebt keine personenbezogenen Daten.",
        "app_h": "Die App",
        "site_h": "Diese Website",
        "gc_h": "Game Center",
        "rights_h": "Ihre Rechte",
        "controller_h": "Verantwortlich",
    },
    "imprint": {
        "title": "Impressum — Keezly",
        "meta": "Impressum und Anbieterkennzeichnung.",
        "h1": "Impressum",
        "responsible_h": "Verantwortlich für den Inhalt",
    },
    "a11y": {
        "title": "Barrierefreiheit — Keezly",
        "meta": "Wie Keezly mit VoiceOver, großer Schrift und ohne Farbunterscheidung "
                "bedient werden kann.",
        "h1": "Barrierefreiheit",
        "lede": "Diese Seite beschreibt nur, was tatsächlich umgesetzt und geprüft ist.",
    },
    "foot_note": "Keezly ist ein unabhängiges Projekt und steht in keiner Verbindung zu "
                 "Apple Inc.",
}

# ------------------------------------------------------------------- Dutch
T["nl"] = {
    "lang": "nl",
    "dir": "ltr",
    "site_name": "Keezly",
    "nav": {"home": "Start", "support": "Hulp", "privacy": "Privacy",
            "imprint": "Colofon", "a11y": "Toegankelijkheid"},
    "skip": "Naar de inhoud",
    "home": {
        "title": "Keezly: Keezenspel — het bordspel voor iPhone en iPad",
        "meta": "Keezen voor twee tot zes spelers, op één apparaat of tegen de "
                "computer. Geen account, geen advertenties, geen tracking.",
        "h1": "Keezly",
        "tagline": "Het Nederlandse bordspel, voor twee tot zes spelers.",
        "lede": "Vier pionnen het bord rond, de anderen eruit slaan, alle vier veilig "
                "thuisbrengen. Geef het apparaat door aan tafel of speel tegen drie "
                "computersterktes — offline, zonder account, zonder advertenties.",
        "badges": ["iPhone en iPad", "2–6 spelers", "Nederlands · Deutsch · English",
                   "Geen advertenties", "Geen tracking"],
        "features_h": "Wat Keezly kan",
        "features": [
            ("Twee tot zes spelers",
             "In teams of ieder voor zich. Met twee, drie, vier, vijf of zes aan tafel — "
             "het bord past zich aan, de regels blijven dezelfde."),
            ("Doorgeven, zoals het hoort",
             "Het apparaat gaat de tafel rond. Als jij aan de beurt bent, wacht het "
             "scherm tot je bevestigt dat je het vasthebt — zo ziet niemand andermans "
             "kaarten."),
            ("Drie computertegenstanders",
             "Makkelijk speelt netjes volgens de regels. Gemiddeld let op zijn eigen "
             "pionnen. Moeilijk leest de stelling en slaat je eruit. Vrij te mengen."),
            ("Jouw huisregels",
             "Wat de heer mag, of een extra ronde is toegestaan, of je eigen pionnen "
             "blokkeren, of je je partner eruit mag slaan, of het huis strikt van "
             "achteren wordt gevuld — elke regel is een schakelaar."),
            ("In tien minuten geleerd",
             "Een uitleg die leert door te spelen in plaats van te lezen, en een "
             "spelregelboek dat je midden in een beurt kunt openen."),
            ("Nog eens terugkijken",
             "Elke afgelopen partij wordt bewaard en kun je zet voor zet terugkijken. "
             "De statistieken worden uit die partijen berekend."),
            ("Game Center",
             "Optioneel en vriendschappelijk: een spel om de beurt via Apple Game "
             "Center, als je dat wilt. Zonder aan te melden speelt Keezly net zo goed."),
            ("Toegankelijk te bedienen",
             "Volledige VoiceOver-ondersteuning, Dynamic Type, een lijst met alle "
             "toegestane zetten en bediening die niet van kleur afhangt."),
        ],
        "shots_h": "Uit het spel",
        "privacy_h": "Wat Keezly niet doet",
        "privacy_p": "Geen account. Geen advertenties. Geen aankopen. Geen tracking, "
                     "geen analyse, geen gegevens die het apparaat verlaten. Keezly "
                     "werkt in vliegtuigmodus, want er is niets om verbinding mee te "
                     "maken.",
        "privacy_link": "Uitgebreid in de privacyverklaring",
    },
    "support": {
        "title": "Hulp bij Keezly",
        "meta": "Contact en hulp bij Keezly: Keezenspel.",
        "h1": "Hulp",
        "intro": "Vragen, foutmeldingen en suggesties gaan naar hetzelfde adres.",
        "contact_h": "Contact",
        "email_label": "E-mail",
        "hub_label": "Centrale supportpagina",
        "faq_h": "Veelgestelde vragen",
        "faq": [
            ("Heb ik internet nodig?",
             "Nee. Alle lokale modi — tegen de computer en doorgeven aan tafel — werken "
             "volledig offline. Alleen een Game Center-partij heeft verbinding nodig."),
            ("Heb ik een account nodig?",
             "Nee. Keezly heeft geen eigen aanmelding. Game Center is optioneel en komt "
             "van Apple."),
            ("Waar worden mijn partijen bewaard?",
             "Op het apparaat, in de map van de app. Ze verdwijnen als je de app "
             "verwijdert."),
            ("Kan ik de regels aanpassen?",
             "Ja. De huisregels waar families ruzie over maken zijn los in te stellen, "
             "en er zijn twee kant-en-klare instellingen."),
        ],
        "response_note": "Deze pagina belooft geen reactietijd. Voor Keezly bestaan geen "
                         "toezeggingen over behandelduur.",
    },
    "privacy": {
        "title": "Privacy — Keezly",
        "meta": "Privacyverklaring voor de Keezly-app en deze website.",
        "h1": "Privacy",
        "lede": "Keezly verzamelt geen persoonsgegevens.",
        "app_h": "De app",
        "site_h": "Deze website",
        "gc_h": "Game Center",
        "rights_h": "Je rechten",
        "controller_h": "Verwerkingsverantwoordelijke",
    },
    "imprint": {
        "title": "Colofon — Keezly",
        "meta": "Colofon en aanbiedergegevens.",
        "h1": "Colofon",
        "responsible_h": "Verantwoordelijk voor de inhoud",
    },
    "a11y": {
        "title": "Toegankelijkheid — Keezly",
        "meta": "Hoe Keezly te bedienen is met VoiceOver, grote tekst en zonder "
                "kleuronderscheid.",
        "h1": "Toegankelijkheid",
        "lede": "Deze pagina beschrijft alleen wat werkelijk is gebouwd en getest.",
    },
    "foot_note": "Keezly is een onafhankelijk project en staat los van Apple Inc.",
}

# ------------------------------------------------------------------ English
T["en"] = {
    "lang": "en",
    "dir": "ltr",
    "site_name": "Keezly",
    "nav": {"home": "Home", "support": "Support", "privacy": "Privacy",
            "imprint": "Imprint", "a11y": "Accessibility"},
    "skip": "Skip to content",
    "home": {
        "title": "Keezly: Keezenspel — the Dutch board game for iPhone and iPad",
        "meta": "Keezen for two to six players, on one device or against the computer. "
                "No account, no advertising, no tracking.",
        "h1": "Keezly",
        "tagline": "The Dutch board game, for two to six players.",
        "lede": "Run four pieces around the board, knock the others back, and get all "
                "four safely home. Pass the device around the table or play three "
                "computer strengths — offline, no account, no advertising.",
        "badges": ["iPhone and iPad", "2–6 players", "English · Deutsch · Nederlands",
                   "No advertising", "No tracking"],
        "features_h": "What Keezly does",
        "features": [
            ("Two to six players",
             "In teams or every player for themselves. Two, three, four, five or six at "
             "the table — the board adapts to the table size, the rules do not change."),
            ("Pass and play, properly",
             "Hand the device around the table. When it is your turn the screen waits "
             "until you say you are holding it, so nobody sees a hand that is not "
             "theirs."),
            ("Three computer opponents",
             "Easy plays legally and cheerfully. Medium looks after its own pieces. "
             "Hard reads the position and will take yours. Mix them at one table."),
            ("The rules you play by",
             "What a King does, whether you may take another lap before going home, "
             "whether your own pieces block you, whether you may knock your partner "
             "back, whether home fills strictly from the back — each is a switch."),
            ("Learn it in ten minutes",
             "A tutorial that teaches by playing rather than by reading, and a rulebook "
             "you can open mid-turn."),
            ("Watch it again",
             "Every finished match is saved and can be replayed move by move. Your "
             "statistics are worked out from those matches."),
            ("Game Center",
             "Optional and friendly: a turn-based match through Apple's Game Center if "
             "you want one. Keezly plays exactly the same without signing in."),
            ("Built to be used",
             "Full VoiceOver support, Dynamic Type, a complete list of legal moves, and "
             "an interface that never depends on colour alone."),
        ],
        "shots_h": "From the game",
        "privacy_h": "What Keezly does not do",
        "privacy_p": "No account. No advertising. No purchases. No tracking, no "
                     "analytics, no data leaving your device. Keezly works with "
                     "aeroplane mode on, because there is nothing for it to connect to.",
        "privacy_link": "Set out in full in the privacy policy",
    },
    "support": {
        "title": "Keezly support",
        "meta": "Contact and help for Keezly: Keezenspel.",
        "h1": "Support",
        "intro": "Questions, bug reports and suggestions all go to the same address.",
        "contact_h": "Contact",
        "email_label": "Email",
        "hub_label": "Central support site",
        "faq_h": "Common questions",
        "faq": [
            ("Do I need an internet connection?",
             "No. Every local mode — against the computer and passing the device around "
             "a table — works entirely offline. Only a Game Center match needs a "
             "connection."),
            ("Do I need an account?",
             "No. Keezly has no sign-in of its own. Game Center is optional and is "
             "provided by Apple."),
            ("Where are my matches stored?",
             "On the device, in the app's own container. They go away when the app is "
             "deleted."),
            ("Can I change the rules?",
             "Yes. The house rules families argue about are individual switches, and "
             "two ready-made presets are there to play straight away."),
        ],
        "response_note": "This page promises no response time. No commitment about "
                         "turnaround exists for Keezly.",
    },
    "privacy": {
        "title": "Privacy — Keezly",
        "meta": "Privacy policy for the Keezly app and this website.",
        "h1": "Privacy",
        "lede": "Keezly collects no personal data.",
        "app_h": "The app",
        "site_h": "This website",
        "gc_h": "Game Center",
        "rights_h": "Your rights",
        "controller_h": "Controller",
    },
    "imprint": {
        "title": "Imprint — Keezly",
        "meta": "Imprint and provider identification.",
        "h1": "Imprint",
        "responsible_h": "Responsible for content",
    },
    "a11y": {
        "title": "Accessibility — Keezly",
        "meta": "How Keezly can be used with VoiceOver, larger text and without "
                "relying on colour.",
        "h1": "Accessibility",
        "lede": "This page describes only what is actually built and tested.",
    },
    "foot_note": "Keezly is an independent project and is not affiliated with Apple Inc.",
}
