"""Legt in GLPI Ticket-Kategorien, Wissensdatenbank-Artikel und Beispieltickets an.

Aufruf:  GLPI_URL=http://127.0.0.1:8080 GLPI_USER=glpi GLPI_PASS=... python seed.py
Das Skript ist wiederholbar: Was es schon gibt, wird nicht doppelt angelegt.
"""
import base64
import json
import os
import urllib.request

URL = os.environ.get("GLPI_URL", "http://127.0.0.1:8080").rstrip("/") + "/apirest.php"
USER = os.environ.get("GLPI_USER", "glpi")
PASS = os.environ["GLPI_PASS"]


def call(method, path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Session-Token"] = token
    else:
        headers["Authorization"] = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


def find(token, itemtype, name):
    rows = call("GET", f"/{itemtype}?range=0-999", token=token) or []
    return next((r["id"] for r in rows if r.get("name") == name), None)


def ensure(token, itemtype, fields):
    existing = find(token, itemtype, fields["name"])
    if existing:
        return existing
    return call("POST", f"/{itemtype}", {"input": fields}, token=token)["id"]


KATEGORIEN = [
    ("Konto und Passwort", "Gesperrte Konten, Passwort vergessen, neue Berechtigungen"),
    ("Netzlaufwerke", "P:-Laufwerk fehlt, kein Zugriff auf Abteilungsordner"),
    ("Hardware", "Notebook, Monitor, Dockingstation, Peripherie"),
    ("Software", "Installation, Updates, Fehlermeldungen"),
    ("Onboarding / Offboarding", "Ein- und Austritte von Mitarbeitenden"),
]

ARTIKEL = [
    ("Passwort zurücksetzen und Konto entsperren", r"""
<p><b>Symptom:</b> Anmeldung schlägt fehl, Meldung „Das Konto ist gesperrt“.</p>
<p>Nach 5 falschen Versuchen sperrt die Domäne das Konto für 15 Minuten.</p>
<ol>
<li>Identität des Anrufers prüfen (Rückruf an hinterlegte Nummer).</li>
<li>Auf DC01: <code>Unlock-ADAccount -Identity vorname.nachname</code></li>
<li>Wenn das Passwort vergessen ist: <code>Set-ADAccountPassword -Identity vorname.nachname -Reset</code>, danach <code>Set-ADUser vorname.nachname -ChangePasswordAtLogon $true</code></li>
<li>Einmalpasswort nie per E-Mail, nur telefonisch oder persönlich.</li>
</ol>"""),
    ("Netzlaufwerk P: fehlt", r"""
<p><b>Symptom:</b> Im Explorer fehlt das Laufwerk P: (Abteilungsordner).</p>
<ol>
<li>Prüfen, ob das Gerät im Firmennetz ist: <code>Test-NetConnection lnx01.lab.local -Port 445</code></li>
<li>Gruppen prüfen: <code>whoami /groups | findstr GG_</code>. Ohne Abteilungsgruppe gibt es kein P:.</li>
<li>Anmeldeskript manuell starten: <code>\\lab.local\NETLOGON\netzlaufwerke.cmd</code></li>
<li>Wurde die Gruppe gerade erst vergeben: einmal ab- und wieder anmelden.</li>
</ol>"""),
    ("Neue Mitarbeiterin / neuen Mitarbeiter anlegen", r"""
<ol>
<li>Daten von HR in <code>neue-mitarbeitende.csv</code> eintragen (Vorname; Nachname; Abteilung; Funktion; Eintritt).</li>
<li>Probelauf: <code>.\02-onboarding.ps1 -Csv .\neue-mitarbeitende.csv -WhatIf</code></li>
<li>Echt ausführen. Das Skript legt das Konto an, setzt die Abteilungsgruppe und schreibt die Startpasswörter in <code>C:\IT\Onboarding</code> (nur für Admins lesbar).</li>
<li>Startpasswort persönlich übergeben, bei der ersten Anmeldung muss es geändert werden.</li>
</ol>"""),
    ("Mitarbeiter verlässt das Unternehmen", r"""
<ol>
<li>Ticket mit Austrittsdatum muss vorliegen.</li>
<li><code>.\05-offboarding.ps1 -Benutzer vorname.nachname -Ticket &lt;Ticketnummer&gt;</code></li>
<li>Das Skript sperrt das Konto, setzt ein Zufallspasswort, entfernt alle Gruppen, verschiebt nach OU Deaktiviert und protokolliert.</li>
<li>Geräte zurücknehmen und in GLPI dem Lager zuordnen.</li>
</ol>"""),
]

TICKETS = [
    ("Konto gesperrt nach Urlaub", "Konto und Passwort", "lena.pichler",
     "Hallo, ich komme aus dem Urlaub und kann mich nicht mehr anmelden. Es steht, dass mein Konto gesperrt ist. Lg Lena",
     "Konto mit Unlock-ADAccount entsperrt, Passwort telefonisch zurückgesetzt, Änderung bei Anmeldung erzwungen."),
    ("Kein P:-Laufwerk am neuen Notebook", "Netzlaufwerke", "tobias.mayer",
     "Seit dem Tausch meines Notebooks fehlt das Laufwerk P:. Tobias, Lohnverrechnung",
     "Benutzer war noch nicht in GG_Buchhaltung. Gruppe ergänzt, nach Neuanmeldung ist P: da."),
    ("Zweiter Monitor bleibt schwarz", "Hardware", "juergen.hofer",
     "Der zweite Bildschirm an der Dockingstation zeigt nichts an. Kabel habe ich schon getauscht.", None),
    ("Eintritt 01.12.: Marie Leitner, Marketing", "Onboarding / Offboarding", "anna.gruber",
     "Neue Kollegin ab 01.12. im Marketing. Bitte Konto, Notebook und Zugriff auf Abteilungsordner vorbereiten. Die Abteilung Marketing gibt es im AD noch nicht.", None),
    ("Excel stürzt beim Öffnen der Preisliste ab", "Software", "maximilian.bauer",
     "Excel schließt sich sofort, wenn ich die Preisliste auf P: öffne. Andere Dateien gehen.", None),
]


def main():
    token = call("GET", "/initSession")["session_token"]
    try:
        kat = {name: ensure(token, "ITILCategory", {"name": name, "comment": text}) for name, text in KATEGORIEN}
        for titel, html in ARTIKEL:
            if not find(token, "KnowbaseItem", titel):
                kb = call("POST", "/KnowbaseItem", {"input": {"name": titel, "answer": html.strip(), "is_faq": 1}}, token=token)["id"]
                call("POST", "/Entity_KnowbaseItem",
                     {"input": {"knowbaseitems_id": kb, "entities_id": 0, "is_recursive": 1}}, token=token)
        for titel, kategorie, melder, text, loesung in TICKETS:
            melder_id = find(token, "User", melder)
            tid = find(token, "Ticket", titel)
            if tid:
                if melder_id and not call("GET", f"/Ticket/{tid}/Ticket_User", token=token):
                    call("POST", "/Ticket_User", {"input": {"tickets_id": tid, "users_id": melder_id, "type": 1}}, token=token)
                continue
            tid = call("POST", "/Ticket", {"input": {"name": titel, "content": text, "itilcategories_id": kat[kategorie],
                                                     "type": 1, "urgency": 3, "_users_id_requester": melder_id or 0}},
                       token=token)["id"]
            if loesung:
                call("POST", "/ITILSolution", {"input": {"itemtype": "Ticket", "items_id": tid, "content": loesung}}, token=token)
        print(f"{len(kat)} Kategorien, {len(ARTIKEL)} Artikel, {len(TICKETS)} Tickets angelegt oder schon vorhanden")
    finally:
        call("GET", "/killSession", token=token)


if __name__ == "__main__":
    main()
