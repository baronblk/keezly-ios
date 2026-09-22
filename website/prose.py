# -*- coding: utf-8 -*-
"""The long-form legal and accessibility text, one literal per language.

Two sources of truth, and no third:

* **The Impressum and the hosting statement** are transcribed from the owner's
  own published pages (`support.gcng.de/legal/impressum.html` and
  `/legal/datenschutz.html`, read 2026-09-22). Nothing about the legal entity,
  the address or where the server stands is written from imagination here.
* **What the app does with data** is read out of the code: `Preferences` and
  `Welcome` write three keys to `UserDefaults`, `MatchStore` writes saved
  matches into Application Support, and `GameCenterTransport` is the only file
  in the project that touches a network at all.

Anything neither source settles is marked `LEGAL REVIEW REQUIRED` in place,
visibly, rather than filled in with something plausible. A privacy policy that
guesses is worse than one that admits a gap.
"""

REVIEW = ("LEGAL REVIEW REQUIRED", "LEGAL REVIEW REQUIRED", "LEGAL REVIEW REQUIRED")

PRIVACY_BODY = {}
IMPRINT_NOTE = {}
A11Y_BODY = {}

# ------------------------------------------------------------------- German
PRIVACY_BODY["de"] = """
    <p>Das ist keine beruhigende Zusammenfassung eines Textes, der weiter unten
    etwas anderes sagt, sondern die ganze Tatsache: Keezly hat kein Konto, keine
    Analyse, keine Werbekennung, keinen Absturzmelder, kein Drittanbieter-SDK
    und im ausgelieferten Spiel keinen eigenen Netzwerkcode. Wenn Sie den
    Flugmodus einschalten, ändert sich am Verhalten der lokalen Spielmodi
    nichts.</p>

    <h2>Die App</h2>
    <p>Alles, was Keezly speichert, liegt auf dem Gerät im Bereich der App und
    verschwindet, wenn die App gelöscht wird.</p>
    <table>
      <thead><tr><th>Was</th><th>Wo</th><th>Wozu</th></tr></thead>
      <tbody>
        <tr><td>Schalter für Ton und Haptik</td><td><code>UserDefaults</code></td>
            <td>Damit eine Einstellung einen Neustart übersteht</td></tr>
        <tr><td>Ob der Willkommensbildschirm gesehen wurde</td><td><code>UserDefaults</code></td>
            <td>Damit er nicht zweimal erscheint</td></tr>
        <tr><td>Gespeicherte Partien</td><td>Ordner „Application Support“ der App</td>
            <td>Fortsetzen, Wiedergabe und Statistik</td></tr>
      </tbody>
    </table>
    <p>Eine gespeicherte Partie besteht aus einem Startwert und der Liste der
    ausgeführten Züge, dazu den Einstellungen des Tisches, einer Partie-Kennung
    und zwei Zeitstempeln. Die Partie-Kennung ist eine beim Austeilen erzeugte
    <code>UUID</code>: sie bezeichnet diese Partie, nicht ein Gerät und nicht
    eine Person. Sie ist weder die Werbekennung noch die Kennung für Anbieter
    noch etwas aus der Hardware Abgeleitetes. Die beiden Zeitstempel sagen,
    wann ausgeteilt und wann zuletzt gezogen wurde; daraus entsteht die
    Reihenfolge in der Liste. Ein Name steht nirgends darin — Plätze sind
    Zahlen.</p>
    <p>Die Statistik wird beim Öffnen aus den gespeicherten Partien berechnet
    und nicht daneben noch einmal geführt. Wer eine Partie löscht, löscht sie
    damit auch aus der Statistik.</p>

    <h2>Diese Website</h2>
    <p>Diese Seiten sind statisch. Es gibt kein Analysewerkzeug, keinen
    Werbetracker, keine eingebetteten Schriften von fremden Servern, kein
    Drittanbieter-JavaScript und keine Cookies, die diese Seite setzt.</p>
    <p>Die Seite wird nach Angabe des Verantwortlichen auf einem selbst
    betriebenen Server innerhalb der Europäischen Union bereitgestellt. Welche
    Zugriffsdaten dieser Server protokolliert und wie lange er sie aufbewahrt,
    ist in der zentralen Datenschutzerklärung unter
    <a href="https://support.gcng.de/legal/datenschutz.html">support.gcng.de</a>
    geregelt; für Keezly gelten keine abweichenden Regeln.</p>

    <h2>Game Center</h2>
    <p>Keezly kann eine rundenbasierte Partie über Apples Game Center spielen.
    Das ist freiwillig: ohne Anmeldung sind alle lokalen Modi vollständig
    nutzbar.</p>
    <p>Game Center ist ein Dienst von Apple. Wenn Sie ihn nutzen, verarbeitet
    Apple die dafür nötigen Daten nach Apples eigener Datenschutzerklärung.
    Keezly überträgt dabei den Spielstand der laufenden Partie und sonst
    nichts. Es gibt <strong>keine</strong> Bestenlisten: Ergebnisse aus dem Netz
    lassen sich nicht ehrlich vergleichen, solange ein verändertes Gerät jedes
    Blatt mitlesen kann, und eine solche Liste würde eine Fairness
    behaupten, die diese Software nicht einlösen kann.</p>

    <h2>Kinder</h2>
    <p>Keezen ist ein Familienspiel, und Kinder werden es spielen. Das ist der
    Grund, warum die Listen oben so kurz sind, und nicht der Anlass für eine
    gesonderte Erklärung: Es gibt keine Datenerhebung zu begrenzen, keine
    Werbung mit Altersfreigabe und keine Kommunikationsfunktion zu moderieren.</p>

    <h2>Ihre Rechte</h2>
    <p>Nach der Datenschutz-Grundverordnung haben Sie unter anderem das Recht
    auf Auskunft, Berichtigung, Löschung und Einschränkung der Verarbeitung
    sowie ein Beschwerderecht bei einer Aufsichtsbehörde. Da Keezly keine
    personenbezogenen Daten an den Verantwortlichen übermittelt, gibt es in
    Bezug auf die App in aller Regel nichts, worüber Auskunft erteilt werden
    könnte. Daten, die auf Ihrem Gerät liegen, löschen Sie, indem Sie die
    Partie oder die App entfernen.</p>

    <h2>Verantwortlich</h2>
    <p>Die Angaben zum Verantwortlichen stehen im
    <a href="../impressum/">Impressum</a>. Fragen zum Datenschutz gehen an
    <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""

IMPRINT_NOTE["de"] = """
    <div class="note">
      <p>Diese Angaben sind von der bestehenden Rechtsseite des Anbieters
      übernommen (<a href="https://support.gcng.de/legal/impressum.html">support.gcng.de</a>,
      Stand 22.09.2026). Eine Umsatzsteuer-Identifikationsnummer ist dort nicht
      angegeben und wird hier deshalb auch nicht genannt.</p>
      <p><strong>Entwurf — rechtliche Prüfung erforderlich.</strong> Ob für
      Keezly zusätzliche Angaben nötig sind, hat ein Mensch zu entscheiden.</p>
    </div>
"""

A11Y_BODY["de"] = """
    <h2>VoiceOver</h2>
    <p>Das Brett ist vollständig vorlesbar. Jedes Feld, jede Figur und jeder Zug
    hat eine gesprochene Beschreibung, und die Ansage nennt neben der Farbe
    immer auch Form und Symbol des Spielers — wer Farben nicht unterscheidet,
    verliert dadurch keine Information.</p>

    <h2>Ohne Farbe bedienbar</h2>
    <p>Spielerzugehörigkeit, Startfelder, Zielfelder, mögliche Züge, Auswahl und
    geschützte Figuren sind jeweils zusätzlich über Form, Symbol oder Kontur
    erkennbar. Das wurde in Graustufen geprüft.</p>

    <h2>Dynamische Schrift</h2>
    <p>Die Texte der App folgen der eingestellten Schriftgröße bis zu den großen
    Bedienungshilfen-Größen. Die Bedienelemente wachsen mit; nichts wird
    abgeschnitten und nichts rutscht aus dem Bild.</p>

    <h2>Liste der erlaubten Züge</h2>
    <p>Neben dem Brett gibt es eine vollständige Liste aller Züge, die gerade
    erlaubt sind. Sie ist nicht hinter einer Bedienungshilfen-Einstellung
    versteckt: Wer das Brett fummelig findet — auf einem kleinen Gerät, mit
    zittriger Hand, in der Sonne — erreicht sie genauso.</p>

    <h2>Bewegung</h2>
    <p>Bei aktiviertem „Bewegung reduzieren“ werden die Animationen auf ein
    Minimum zurückgenommen.</p>

    <h2>Tastatur und Zeigegerät</h2>
    <p>Auf dem iPad lassen sich Hand und Brett mit den Pfeiltasten durchgehen,
    die Eingabetaste führt aus, Escape bricht ab. Der Fokusrahmen ist in
    Schwarz und Weiß gezeichnet und damit unabhängig von der Farbe erkennbar.</p>

    <div class="note">
      <p>Was hier steht, ist umgesetzt und geprüft. Eine Prüfung mit
      Tastatur und Zeigegerät auf echter Hardware steht noch aus, weil dafür
      Geräte fehlen; das ist im Projekt als offener Punkt vermerkt.</p>
    </div>

    <h2>Rückmeldung</h2>
    <p>Wenn Ihnen etwas begegnet, das sich nicht bedienen lässt, schreiben Sie
    bitte an <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""

# -------------------------------------------------------------------- Dutch
PRIVACY_BODY["nl"] = """
    <p>Dat is geen geruststellende samenvatting van een tekst die verderop iets
    anders zegt, maar het hele feit: Keezly heeft geen account, geen analyse,
    geen advertentie-id, geen crashmelder, geen SDK van derden en in het
    uitgeleverde spel geen eigen netwerkcode. Zet u de vliegtuigmodus aan, dan
    verandert er niets aan de lokale spelmodi.</p>

    <h2>De app</h2>
    <p>Alles wat Keezly bewaart staat op het apparaat, in de map van de app, en
    verdwijnt als de app wordt verwijderd.</p>
    <table>
      <thead><tr><th>Wat</th><th>Waar</th><th>Waarvoor</th></tr></thead>
      <tbody>
        <tr><td>Schakelaars voor geluid en haptiek</td><td><code>UserDefaults</code></td>
            <td>Zodat een voorkeur een herstart overleeft</td></tr>
        <tr><td>Of het welkomstscherm is gezien</td><td><code>UserDefaults</code></td>
            <td>Zodat het niet twee keer verschijnt</td></tr>
        <tr><td>Bewaarde partijen</td><td>De map „Application Support” van de app</td>
            <td>Hervatten, terugkijken en statistieken</td></tr>
      </tbody>
    </table>
    <p>Een bewaarde partij bestaat uit een startgetal en de lijst met gedane
    zetten, plus de instellingen van de tafel, een partij-id en twee
    tijdstempels. Dat partij-id is een <code>UUID</code> die bij het delen wordt
    gemaakt: het benoemt die partij, niet een apparaat en niet een persoon. Het
    is niet de advertentie-id, niet de identificatie voor leveranciers en niet
    iets dat uit de hardware is afgeleid. De twee tijdstempels zeggen wanneer er
    is gedeeld en wanneer er voor het laatst is gezet; daarmee staat de lijst op
    volgorde. Er staat nergens een naam in — plaatsen zijn nummers.</p>
    <p>De statistieken worden bij het openen uit die partijen berekend en niet
    daarnaast nog eens bijgehouden. Wie een partij verwijdert, verwijdert hem
    daarmee ook uit de statistieken.</p>

    <h2>Deze website</h2>
    <p>Deze pagina's zijn statisch. Er is geen analysetool, geen advertentie­
    tracker, geen lettertype van een vreemde server, geen JavaScript van derden
    en geen cookie die deze pagina plaatst.</p>
    <p>De site wordt volgens opgave van de verwerkingsverantwoordelijke
    aangeboden vanaf een zelf beheerde server binnen de Europese Unie. Welke
    toegangsgegevens die server vastlegt en hoe lang hij ze bewaart, staat in de
    centrale privacyverklaring op
    <a href="https://support.gcng.de/legal/datenschutz.html">support.gcng.de</a>;
    voor Keezly gelden geen afwijkende regels.</p>

    <h2>Game Center</h2>
    <p>Keezly kan een partij om de beurt spelen via Apple Game Center. Dat is
    vrijwillig: zonder aanmelding zijn alle lokale modi volledig bruikbaar.</p>
    <p>Game Center is een dienst van Apple. Gebruikt u hem, dan verwerkt Apple
    de daarvoor benodigde gegevens volgens Apples eigen privacyverklaring.
    Keezly stuurt daarbij de stand van de lopende partij en verder niets. Er
    zijn <strong>geen</strong> ranglijsten: resultaten uit het net laten zich
    niet eerlijk vergelijken zolang een aangepast apparaat elke hand kan
    meelezen, en een ranglijst zou een eerlijkheid beweren die deze software
    niet kan waarmaken.</p>

    <h2>Kinderen</h2>
    <p>Keezen is een familiespel en kinderen zullen het spelen. Dat is de reden
    dat de lijsten hierboven zo kort zijn, en niet de aanleiding voor een aparte
    verklaring: er is geen gegevensverzameling om te beperken, geen advertentie
    met leeftijdsgrens en geen communicatiefunctie om te modereren.</p>

    <h2>Je rechten</h2>
    <p>Op grond van de AVG heeft u onder meer recht op inzage, rectificatie,
    verwijdering en beperking van de verwerking, en het recht een klacht in te
    dienen bij een toezichthouder. Omdat Keezly geen persoonsgegevens naar de
    verwerkingsverantwoordelijke stuurt, valt er over de app in de regel niets
    in te zien. Gegevens op uw apparaat verwijdert u door de partij of de app te
    verwijderen.</p>

    <h2>Verwerkingsverantwoordelijke</h2>
    <p>De gegevens staan in het <a href="../colofon/">colofon</a>. Vragen over
    privacy gaan naar <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""

IMPRINT_NOTE["nl"] = """
    <div class="note">
      <p>Deze gegevens zijn overgenomen van de bestaande rechtspagina van de
      aanbieder (<a href="https://support.gcng.de/legal/impressum.html">support.gcng.de</a>,
      geraadpleegd 22-09-2026). Daar staat geen btw-identificatienummer vermeld,
      dus het wordt hier ook niet genoemd.</p>
      <p><strong>Concept — juridische toetsing vereist.</strong> Of Keezly
      aanvullende vermeldingen nodig heeft, is aan een mens om te beoordelen.</p>
    </div>
"""

A11Y_BODY["nl"] = """
    <h2>VoiceOver</h2>
    <p>Het bord is volledig voor te lezen. Elk vakje, elke pion en elke zet heeft
    een gesproken beschrijving, en de aankondiging noemt naast de kleur altijd
    ook de vorm en het symbool van de speler — wie kleuren niet onderscheidt,
    verliest daardoor geen informatie.</p>

    <h2>Zonder kleur te bedienen</h2>
    <p>Bij welke speler een pion hoort, startvakjes, huisvakjes, mogelijke
    zetten, selectie en beschermde pionnen zijn steeds ook aan vorm, symbool of
    contour te zien. Dat is in grijstinten gecontroleerd.</p>

    <h2>Dynamic Type</h2>
    <p>De teksten volgen de ingestelde tekstgrootte tot en met de grote
    toegankelijkheidsformaten. De bedieningselementen groeien mee; er wordt niets
    afgekapt en er valt niets buiten beeld.</p>

    <h2>Lijst met toegestane zetten</h2>
    <p>Naast het bord is er een volledige lijst met alle zetten die op dat moment
    mogen. Die zit niet verstopt achter een toegankelijkheidsinstelling: wie het
    bord priegelig vindt — op een klein apparaat, met een trillende hand, in de
    zon — komt er net zo goed bij.</p>

    <h2>Beweging</h2>
    <p>Met „Verminder beweging” aan worden de animaties tot een minimum
    teruggebracht.</p>

    <h2>Toetsenbord en aanwijsapparaat</h2>
    <p>Op de iPad zijn hand en bord met de pijltoetsen te doorlopen, Enter voert
    uit en Escape annuleert. De focusrand is in zwart en wit getekend en dus
    onafhankelijk van kleur te zien.</p>

    <div class="note">
      <p>Wat hier staat is gebouwd en getest. Een controle met toetsenbord en
      aanwijsapparaat op echte hardware staat nog open omdat daarvoor apparaten
      ontbreken; dat is in het project als openstaand punt vastgelegd.</p>
    </div>

    <h2>Terugkoppeling</h2>
    <p>Komt u iets tegen dat niet te bedienen is, schrijf dan naar
    <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""

# ------------------------------------------------------------------ English
PRIVACY_BODY["en"] = """
    <p>Not a reassuring summary of a longer document that says otherwise — the
    whole fact. Keezly has no account, no analytics, no advertising identifier,
    no crash reporter, no third-party SDK, and no network code of its own in the
    shipping game. Turning on aeroplane mode changes nothing about how the local
    modes behave.</p>

    <h2>The app</h2>
    <p>Everything Keezly keeps is on the device, in the app's own container, and
    goes away when the app is deleted.</p>
    <table>
      <thead><tr><th>What</th><th>Where</th><th>Why</th></tr></thead>
      <tbody>
        <tr><td>Sound and haptics switches</td><td><code>UserDefaults</code></td>
            <td>So a preference survives a restart</td></tr>
        <tr><td>Whether the welcome screen has been seen</td><td><code>UserDefaults</code></td>
            <td>So it is not shown twice</td></tr>
        <tr><td>Saved matches</td><td>The app's Application Support directory</td>
            <td>Resuming, replaying and the statistics</td></tr>
      </tbody>
    </table>
    <p>A saved match is a seed and the list of accepted actions, together with
    the table's settings, a match id and two times. The match id is a
    <code>UUID</code> made when the match is dealt: it identifies that match, not
    a device and not a person. It is not the advertising identifier, not the
    identifier for vendors, and nothing derived from the hardware. The two times
    are when the match was dealt and when an action was last added, which is what
    puts the history list in order. There is no name anywhere in it — seats are
    numbers.</p>
    <p>Statistics are worked out from those matches when the screen is opened,
    not kept a second time beside them. Deleting a match removes it from the
    statistics too.</p>

    <h2>This website</h2>
    <p>These pages are static. There is no analytics tool, no advertising
    tracker, no font loaded from somebody else's server, no third-party
    JavaScript, and no cookie set by this site.</p>
    <p>The site is served, according to the controller's own statement, from a
    server they operate within the European Union. What access data that server
    records and for how long is governed by the central privacy statement at
    <a href="https://support.gcng.de/legal/datenschutz.html">support.gcng.de</a>;
    no different rules apply to Keezly.</p>

    <h2>Game Center</h2>
    <p>Keezly can play a turn-based match through Apple's Game Center. That is
    voluntary: every local mode works fully without signing in.</p>
    <p>Game Center is Apple's service. If you use it, Apple processes the data it
    needs under Apple's own privacy policy. Keezly sends the state of the match
    in progress and nothing else. There are <strong>no</strong> leaderboards:
    online results cannot be ranked honestly while a modified client can read
    every hand, and such a list would claim a fairness this software cannot
    keep.</p>

    <h2>Children</h2>
    <p>Keezen is a family board game and children will play it. That is why the
    lists above are as short as they are, rather than a reason for a separate
    policy: there is no data collection to limit, no advertising to age-gate and
    no communication feature to moderate.</p>

    <h2>Your rights</h2>
    <p>Under the GDPR you have, among others, the right of access,
    rectification, erasure and restriction of processing, and the right to
    complain to a supervisory authority. Because Keezly sends no personal data
    to the controller, there is generally nothing about the app to give access
    to. Data held on your device is deleted by removing the match or the app.</p>

    <h2>Controller</h2>
    <p>The controller's details are on the <a href="../imprint/">imprint</a>
    page. Privacy questions go to
    <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""

IMPRINT_NOTE["en"] = """
    <div class="note">
      <p>These details are transcribed from the provider's existing legal page
      (<a href="https://support.gcng.de/legal/impressum.html">support.gcng.de</a>,
      read 22 September 2026). No VAT identification number is stated there, so
      none is stated here.</p>
      <p><strong>Draft — human legal review required.</strong> Whether Keezly
      needs any further disclosure is for a person to decide.</p>
    </div>
"""

A11Y_BODY["en"] = """
    <h2>VoiceOver</h2>
    <p>The board reads aloud in full. Every square, every piece and every move
    has a spoken description, and an announcement always names the player's shape
    and symbol alongside the colour — somebody who cannot tell the colours apart
    loses no information.</p>

    <h2>Usable without colour</h2>
    <p>Which player a piece belongs to, start squares, home squares, legal
    targets, selection and protected pieces are each also carried by shape,
    symbol or outline. This was checked in greyscale.</p>

    <h2>Dynamic Type</h2>
    <p>The app's text follows the reader's chosen size, up to the large
    accessibility sizes. Controls grow with it; nothing is truncated and nothing
    slides off the screen.</p>

    <h2>The list of legal moves</h2>
    <p>Beside the board there is a complete list of every move currently allowed.
    It is not hidden behind an accessibility setting: anybody who finds the board
    fiddly — a small device, an unsteady hand, bright sunlight — reaches it the
    same way.</p>

    <h2>Motion</h2>
    <p>With Reduce Motion switched on, the animations are cut back to a
    minimum.</p>

    <h2>Keyboard and pointer</h2>
    <p>On iPad the hand and the board can be walked with the arrow keys, Return
    acts and Escape cancels. The focus ring is drawn in black and white, so it
    does not depend on colour.</p>

    <div class="note">
      <p>What is described here is built and tested. A check with a hardware
      keyboard and pointer on real equipment is still outstanding because the
      hardware is not available; that is recorded as an open item in the
      project.</p>
    </div>

    <h2>Feedback</h2>
    <p>If you meet something you cannot operate, please write to
    <a href="mailto:support@gcng.de">support@gcng.de</a>.</p>
"""
