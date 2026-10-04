# LabZeal vs. Upstream Zeal — Vollständige Änderungsdokumentation

## Übersicht

LabZeal ist ein Hard-Fork von [Zeal](https://zealdocs.org) (einem Offline-Dokumentationsbrowser), der für den gesperrten Einsatz in Labor-/Hörsaal-Umgebungen angepasst wurde. Die Änderungen verfolgen vier Kernziele:

1. **Rebranding** — sämtliche sichtbaren Strings von „Zeal" auf „LabZeal" umstellen
2. **Docset-Pfad hart verdrahten** — auf einen gemeinsam genutzten, schreibgeschützten Systempfad zwingen
3. **Update-Prüfung deaktivieren** — kein Netzwerkverkehr im Labor
4. **UI einfrieren** — Studenten können weder Pfad ändern, noch Docsets herunterladen, noch nach Updates suchen

---

## 1. Quellcode-Änderungen (C++ / CMake / UI)

Insgesamt wurden **14 getrackte Dateien** gegenüber dem Upstream-Zeal verändert (`git diff HEAD` ergibt 45 Einfügungen, 59 Löschungen).

### 1.1 `src/libs/core/settings.cpp` — Kern-Lockdown

Die wichtigste Datei: Hier werden die drei zentralen Lockdown-Maßnahmen implementiert.

**Update-Prüfung deaktiviert:**
```cpp
// Upstream:
#ifdef ZEAL_FEATURE_UPDATE_CHECK
    checkForUpdate = settings->value("check_for_update", true).toBool();
#else
    checkForUpdate = settings->value("check_for_update", false).toBool();
#endif

// LabZeal (hart verdrahtet):
checkForUpdate = false;
```

**Docset-Pfad erzwungen:**
```cpp
// Upstream (dynamisch, benutzerspezifisch):
if (settings->contains("path")) {
    docsetPath = settings->value("path").toString();
} else {
#ifndef PORTABLE_BUILD
    docsetPath = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)
                 + "/docsets";
#else
    docsetPath = "docsets";
#endif
}

// LabZeal (hart verdrahtet):
docsetPath = QStringLiteral("/usr/share/labzeal/docsets");
```

**Menüleiste gesperrt:**
```cpp
// Upstream:
hideMenuBar = settings->value("hide_menu_bar", false).toBool();

// LabZeal:
hideMenuBar = false; // LabZeal lockdown: menu bar always visible.
```

Diese drei Änderungen ignorieren jegliche benutzerspezifische Konfiguration — selbst wenn ein Student `~/.config/LabZeal/LabZeal.conf` manuell editieren würde.

### 1.2 `src/app/CMakeLists.txt` — Binary-Name hart verdrahtet

```cmake
# Upstream (betriebssystemabhängig):
if(APPLE)
    set(_project_output_name ${CMAKE_PROJECT_NAME})     # "Zeal"
else()
    string(TOLOWER ${CMAKE_PROJECT_NAME} _project_output_name)  # "zeal"
endif()

# LabZeal:
set(_project_output_name "labzeal")
```

Die ausführbare Datei heißt immer `labzeal` — unabhängig vom Betriebssystem.

### 1.3 `src/app/main.cpp` — Anwendungsidentität

| Eigenschaft | Upstream | LabZeal |
|---|---|---|
| App-Name | `"Zeal"` | `"LabZeal"` |
| App-Version | `ZEAL_VERSION` (0.8.2-dev) | `ZEAL_VERSION` (unverändert) |
| Organisations-Domain | `"zealdocs.org"` | `"labzeal.local"` |
| Organisations-Name | `"Zeal"` | `"LabZeal"` |
| CLI-Beschreibung | `"Zeal - Offline documentation browser."` | `"LabZeal - Offline documentation browser."` |

Durch die geänderte Organisations-Domain/Name nutzt LabZeal einen separaten QSettings-Pfad (`~/.config/LabZeal/`) und kollidiert nicht mit einer ggf. parallel installierten Zeal-Installation.

### 1.4 `src/libs/ui/mainwindow.cpp` — Fenster + Menü

- Fenstertitel: `"Zeal"` / `"Zeal Portable"` → `"LabZeal"` / `"LabZeal Portable"`
- Update-Prüfung-Menüeintrag **komplett entfernt** (auskommentiert mit `// NOTE: "Check for Updates" intentionally removed for LabZeal lab deployment.`)
- „Über"-Eintrag: `"&About Zeal"` → `"&About LabZeal"`

### 1.5 `src/libs/ui/settingsdialog.cpp` — Einstellungs-UI gesperrt

Nach dem Laden der Einstellungen (`loadSettings()`) werden drei Widgets deaktiviert:

```cpp
// LabZeal lockdown: prevent changing docset path and update check in lab environments.
ui->docsetStorageEdit->setReadOnly(true);           // Pfadfeld schreibgeschützt
ui->docsetStorageBrowseButton->setVisible(false);   // "Durchsuchen"-Button versteckt
ui->checkForUpdateCheckBox->setVisible(false);      // Update-Checkbox versteckt
```

### 1.6 `src/libs/ui/settingsdialog.ui` — Label-Texte

- `"Show Zeal:"` → `"Show LabZeal:"`
- `"Open in Zeal"` → `"Open in LabZeal"`

### 1.7 `src/libs/ui/windowmanager.cpp` — Tray + Dialoge

- Tray-Tooltip: `"Zeal"` → `"LabZeal"`
- Tray-Menü: `"Show Zeal"` → `"Show LabZeal"`
- Update-Dialog-Titel: `"Zeal"` → `"LabZeal"`
- Update-Meldung: `"Zeal <b>%1</b> is available..."` → `"LabZeal <b>%1</b> is available..."`
- Update-Meldung (kein Update): `"You are using the latest version."` (unverändert)

### 1.8 `src/libs/ui/docsetsdialog.cpp` — Dialog-Rebranding

Sämtliche `QMessageBox`- und `QInputDialog`-Titel von `"Zeal"` auf `"LabZeal"` umgestellt (7 Stellen):
- Feed-Hinzufügen-Dialog
- Docset-Entfernen-Bestätigung
- Download-Fehler-Dialoge
- Ungültiger-Feed-Warnung
- Extraktionsfehler
- Beschädigte-Docset-Liste-Warnung
- Löschfehler

### 1.9 `src/libs/ui/aboutdialog.ui` — Über-Dialog

- Fenstertitel: `"About Zeal"` → `"About LabZeal"`
- Überschrift: `<h1>Zeal</h1>` → `<h1>LabZeal</h1>`

### 1.10 `src/libs/core/application.cpp` — User-Agent

- HTTP-User-Agent: `"Zeal/..."` → `"LabZeal/..."`

### 1.11 `src/libs/browser/webpage.cpp` — Externer-Link-Dialog

- Button: `"Open in &Zeal"` → `"Open in &LabZeal"`

### 1.12 `src/app/resources/browser/welcome.html` — Startseite

- Titel: `<h1>Zeal` → `<h1>LabZeal`

### 1.13 `assets/freedesktop/sc-apps-zeal.svg` + `sc-apps-zeal-tray.svg` — Icon-Metadaten

- SVG `<title>` und `<desc>`: `"Zeal"` → `"LabZeal"`

---

## 2. Vorkompiliertes Binary

| Pfad | Größe | Zweck |
|---|---|---|
| `build_packages/labzeal/usr/bin/labzeal` | 2,1 MB | Quellverzeichnis für das Debian-Paket |
| `labzeal-deb/labzeal.deb` | 651 KB | Fertig gebautes `.deb`-Paket |
| `build_packages/labzeal.deb` | 651 KB | Duplikat des `.deb`-Pakets |

Das Binary ist gegen **Qt 6** gelinkt (siehe `Depends` in der `control`-Datei: `libqt6core6`, `libqt6gui6`, `libqt6webenginewidgets6`, usw.).

> **Hinweis:** Die ältere `Prov_Doku.txt` dokumentiert ursprünglich eine Qt-5-Strategie. Der aktuelle Stand (`build_packages/labzeal/DEBIAN/control`) verwendet Qt 6. Das Binary wurde offenbar mit Qt 6 neu gebaut.

---

## 3. Debian-Paketierung (`build_packages/`)

### Paket A: `labzeal` (Kernanwendung)

**`build_packages/labzeal/DEBIAN/control`:**
```
Package: labzeal
Version: 1.0.0
Section: devel
Priority: optional
Architecture: amd64
Depends: libc6, libstdc++6, libqt6core6, libqt6gui6, libqt6widgets6,
         libqt6webenginewidgets6, libqt6network6, libqt6svg6
Maintainer: Alexander Tieber <jungewas40@gmail.com>
Description: LabZeal Core Application (Qt6)
 Modifizierte Zeal Version fuer Laboreinsatz.
 Shared Path forced to /usr/share/labzeal/docsets.
```

**`build_packages/labzeal/DEBIAN/postinst`:**
```sh
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    if [ ! -d "/usr/share/labzeal/docsets" ]; then
        mkdir -p /usr/share/labzeal/docsets
    fi
    chown -R root:root /usr/share/labzeal
    chmod -R 755 /usr/share/labzeal
fi
exit 0
```

Enthält außerdem:
- `usr/share/applications/labzeal.desktop` — Desktop-Eintrag mit MIME-Types für `dash:` und `dash-plugin:` URL-Schemas
- `usr/share/icons/hicolor/48x48/apps/labzeal.png` — 48×48 Icon
- `usr/share/icons/hicolor/256x256/apps/labzeal.png` — 256×256 Icon

### Paket B: `python-labzeal` (Beispiel-Docset)

**`build_packages/python-labzeal/DEBIAN/control`:**
```
Package: python-labzeal
Version: 1.0.0
Section: doc
Priority: optional
Architecture: all
Depends: labzeal
Maintainer: Alexander Tieber <jungewas40@gmail.com>
Description: Python 3 Documentation for LabZeal
 Installs Python 3 docsets into the shared LabZeal path.
```

**`build_packages/python-labzeal/DEBIAN/postinst`:**
```sh
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    DOCSET_PATH="/usr/share/labzeal/docsets/Python_3.docset"
    if [ -d "$DOCSET_PATH" ]; then
        chown -R root:root "$DOCSET_PATH"
        chmod -R a+rX "$DOCSET_PATH"
    fi
fi
exit 0
```

> **Hinweis:** Das `python-labzeal`-Verzeichnis enthält derzeit nur die `DEBIAN`-Metadaten, aber keine tatsächlichen Docset-Dateien unter `usr/share/labzeal/docsets/Python_3.docset/`. Die Docset-Inhalte werden entweder manuell dort abgelegt oder über den `build_all.py`-Workflow aus der Zeal-API heruntergeladen und in separate `labzeal-docset-*`-Pakete verpackt.

---

## 4. Vergleich: Patch-Datei vs. aktueller Arbeitsstand

Die Datei `meine_labzeal_aenderungen.patch` (63 KB) ist ein **historisches Artefakt** und weicht in mehreren Punkten vom aktuellen Arbeitsverzeichnis ab:

| Aspekt | In der Patch-Datei | Im aktuellen Arbeitsverzeichnis |
|---|---|---|
| `postinst`-Dateien | **Gelöscht** (beide Pakete) | **Vorhanden** (beide Pakete) |
| Formatierung | Massive Whitespace-Reform (4→2 Leerzeichen Einrückung) in `main.cpp` und `mainwindow.cpp` | Nur funktionale Änderungen, keine Whitespace-Reform |
| `Prov_Doku.txt` | Dokumentiert Qt-5-Strategie | Arbeitsverzeichnis nutzt Qt 6 (laut control-Dateien) |
| Binary im Repo-Root | Als neue Datei hinzugefügt (`labzeal`) | Nicht vorhanden, nur in `build_packages/` und `labzeal-deb/` |
| `src/app/main.cpp` | Enthält zusätzlich `#include`-Änderungen für `QCommandLineParser` | Aktuelle Version hat weniger Zeilen geändert |

**Fazit:** Der Patch repräsentiert eine ältere Momentaufnahme. Für die aktuelle Dokumentation ist allein das Arbeitsverzeichnis (`git diff HEAD` + untracked files) maßgeblich.

---

## 5. Build- und Deploy-Skripte — Funktionsbeschreibung

### 5.1 `build_all.py` — Docset-Paket-Builder

**Zweck:** Lädt den Docset-Katalog von der Zeal-API, filtert und dedupliziert, baut dann parallel individuelle `.deb`-Pakete und abschließend ein Meta-Paket.

**Aufruf (CLI via argparse):**

| Argument | Typ | Default | Beschreibung |
|---|---|---|---|
| `--limit N` | int | 12 | Maximale Anzahl zu bauender Docsets |
| `--workers N` | int | `min(8, CPU-Kerne)` | Thread-Pool-Größe |
| `--deploy` | flag | false | Führt `deploy_local.sh` nach dem Bau aus |
| `--output DIR` | str | `./labzeal_dist` | Ausgabeverzeichnis für `.deb`-Dateien |
| `--skip-existing` | flag | false | Bereits vorhandene `.deb`-Dateien überspringen |

**Ablauf im Detail:**

1. **API-Abruf** — `GET https://api.zealdocs.org/v1/docsets` liefert den kompletten Docset-JSON-Katalog
2. **Filterung** — behält nur `sourceId == 'com.kapeli'` (offizielle Docsets), schließt `"user contributed"`- und `"cheatsheet"`-Einträge sowie Namen mit Suffix `_contrib`/`_cheatsheet` aus
3. **Deduplizierung** — für versionierte Titel wie `"Bootstrap 5"` vs. `"Bootstrap 4"` wird die Versionsnummer per Regex (`^(.*?)\s*([0-9]+(?:\.[0-9]+)*)$`) geparst; nur die höchste Version pro Basisname bleibt erhalten
4. **Paralleler Bau** — `ThreadPoolExecutor` mit konfigurierbarer Worker-Anzahl:
   - **Download:** Streamt `.tar.gz` von `https://go.zealdocs.org/d/com.kapeli/{name}/latest`, validiert GZip-Magic-Bytes (`\x1f\x8b`)
   - **Entpacken:** Extrahiert mit `tarfile.open(mode="r:gz")` und `filter='data'` (Schutz vor Pfad-Traversal) in `usr/share/labzeal/docsets/`
   - **Icons:** Lädt `icon.png` und `icon@2x.png` von den API-gelieferten URLs herunter (HTTP oder Base64-Data-URIs)
   - **Index:** Durchläuft alle HTML-Dateien im Docset, extrahiert `<title>`-Tags und baut eine SQLite-`searchIndex`-Tabelle in `Contents/Resources/docSet.dsidx`
   - **Paketbau:** Schreibt `DEBIAN/control` (mit Abhängigkeit `labzeal`), ruft `fakeroot dpkg-deb -Zgzip -z1 --build` auf
   - **Aufräumen:** Jeder Build läuft in einem eigenen `tempfile.mkdtemp()`, das per `try/finally` garantiert gelöscht wird
5. **Meta-Paket** — baut `labzeal-all.deb`, das von allen erfolgreich gebauten `labzeal-docset-*`-Paketen abhängt
6. **Optionaler Deploy** — wenn `--deploy` gesetzt ist, wird `bash deploy_local.sh` ausgeführt

**Strategie für Dateirechte:** Die `.deb`-Pakete werden mit `dpkg-deb --root-owner-group` gebaut. Das zwingt alle Dateien im Paket auf `root:root` — ohne `fakeroot` und ohne pro-Paket-`postinst`. Die `labzeal`-`postinst` setzt einmalig `chown root:root /usr/share/labzeal/docsets`. Danach verhindert das root-owned Elternverzeichnis jegliches Löschen/Anlegen durch normale User (Unix-Semantik: Schreibrecht auf das Elternverzeichnis erforderlich). Der App-Code prüft dies via `isDirWritable()` (Zeile 914 in `docsetsdialog.cpp`) und deaktiviert bei read-only-Storage automatisch alle Download-/Remove-/Update-Buttons.

### 5.2 `pipeline.sh` — Build/Deploy-Orchestrator

**Zweck:** Ein-Kommando-Einstieg, der Cleanup → Build → Deploy → Install verkettet.

**Aufruf (while/case CLI):**

| Argument | Wirkung |
|---|---|
| `--limit N` | Anzahl zu bauender Docsets (default: 12) |
| `--workers N` | Thread-Pool-Größe (default: `min(CPU-Kerne, Limit)`) |
| `--full` | Alle neu bauen, kein `--skip-existing` |
| `--deploy` | `deploy_local.sh` nach dem Build ausführen |
| `--install` | Impliziert `--deploy`, danach `sudo apt-get install labzeal-all -y` |
| `--cleanup` | `cleanup.sh` vor dem Build ausführen (löscht alles) |
| `-h`, `--help` | Hilfe anzeigen |

**Phasen:**

1. **Phase 0 (optional):** `bash cleanup.sh` — vollständige Systembereinigung
2. **Phase 1:** `python3 build_all.py --limit $LIMIT --workers $WORKERS [--skip-existing]` — Docset-Pakete bauen
3. **Phase 2 (optional):** `bash deploy_local.sh` — Pakete ins lokale APT-Repo deployen
4. **Phase 3 (optional):** `sudo apt-get install labzeal-all -y` — Meta-Paket installieren/aktualisieren

Die Worker-Anzahl wird automatisch auf das Minimum von CPU-Kernen und Limit gedeckelt, damit nie mehr Threads als Docsets gestartet werden.

### 5.3 `deploy_local.sh` — Lokales APT-Repository einrichten

**Zweck:** Kopiert gebaute `.deb`-Pakete in ein lokales Webverzeichnis und konfiguriert APT darauf.

**Ablauf:**

1. **Backup** — sichert bestehendes `/var/www/html/labzeal/debs/` als `~/labzeal_backup/labzeal_debs_$TIMESTAMP.tar.gz`
2. **Verzeichnis vorbereiten** — `sudo mkdir -p /var/www/html/labzeal/debs`
3. **Pakete kopieren** — aus `./labzeal_dist/*.deb` (Docset-Pakete) und `./labzeal-deb/*.deb` (Core-Paket) nach `/var/www/html/labzeal/debs/`
4. **APT-Index generieren** — `dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz` im Web-Root
5. **APT-Quelle konfigurieren** — schreibt `/etc/apt/sources.list.d/labzeal.sources`:
   ```
   Types: deb
   URIs: http://127.0.0.1/labzeal/
   Suites: /
   Components:
   Trusted: yes
   Enabled: yes
   ```
   Dann `sudo apt-get update -qq`

### 5.4 `cleanup.sh` — Vollständige Systembereinigung

**Zweck:** Entfernt restlos alle LabZeal-Pakete, Konfigurationen und Build-Artefakte vom System.

**Ablauf:**

1. **Prozesse killen** — `pkill -f labzeal` und `pkill -f zeal`
2. **Core-Paket löschen** — `sudo apt-get purge --autoremove labzeal -y`
3. **Meta-Paket löschen** — `sudo apt-get purge --autoremove labzeal-all -y`
4. **Alle Docset-Pakete löschen** — ermittelt mit `dpkg-query` alle `labzeal-docset-*`-Pakete und purged sie
5. **APT-Quellen entfernen** — löscht `/etc/apt/sources.list.d/labzeal.list` und `labzeal.sources`
6. **Build-Artefakte löschen** — `rm -rf ./labzeal_dist`
7. **Webverzeichnis löschen** — `sudo rm -rf /var/www/html/labzeal/`
8. **APT-Cache leeren** — `sudo apt-get update`

### 5.5 `video.sh` — Präsentations-Recorder

**Zweck:** Führt eine komplette Pipeline aus, zeigt die Quellcode-Dateien für die Bildschirmaufnahme an und startet LabZeal. Konzipiert für eine ca. 5-minütige Aufnahme (via GStreamer/Pipewire, Aufruf extern).

**Ablauf:**

1. **Echten Benutzer erkennen** — `REAL_USER=${SUDO_USER:-$USER}` für `su`-Umschaltung
2. **Hilfsfunktionen:**
   - `show_file(label, dateipfad)` — gibt eine formatierte Überschrift aus, `cat`-et die Datei, wartet 5 Sekunden
   - `show_postinst()` — extrahiert das Control-Archiv aus `labzeal-deb/labzeal.deb` via `dpkg-deb --control`, zeigt das `postinst`-Skript an, räumt auf, wartet 3 Sekunden
3. **Pipeline ausführen** — `./pipeline.sh --limit 2 --workers 2 --install --cleanup` (komplette Bereinigung + 2 Docset-Pakete + Deploy + Installation)
4. **Quellcode anzeigen** — nacheinander: `build_all.py`, `cleanup.sh`, `deploy_local.sh`, `pipeline.sh` und das `postinst`-Skript
5. **LabZeal starten** — `su -c "labzeal 'dash://list'" $REAL_USER &` (füllt das Suchfeld mit „list" vor, sodass Suchergebnisse und Docset-Icons sofort sichtbar sind)
6. **Abschluss-Sleep** — 275 Sekunden (füllt die restliche Aufnahmezeit, insgesamt ca. 5 Minuten)

---

## 6. Architektur des Lockdowns — Zusammenfassung

```
┌──────────────────────────────────────────────────┐
│                LabZeal Lockdown                   │
├──────────────────────────────────────────────────┤
│  Binary-Name         │ hart verdrahtet "labzeal" │
│  Docset-Pfad         │ /usr/share/labzeal/docsets │
│  Pfad im UI          │ schreibgeschützt,          │
│                      │ "Durchsuchen" versteckt    │
│  Update-Prüfung      │ deaktiviert (Code + UI)    │
│  Update-Menüpunkt    │ aus Menüleiste entfernt    │
│  Menüleiste          │ immer sichtbar             │
│  Berechtigungen      │ root:root, 755 (postinst)  │
│  Docset-Auslieferung │ via separate .deb-Pakete   │
│  APT-Repo            │ lokal (127.0.0.1/labzeal)  │
│  QSettings-Namespace │ ~/.config/LabZeal/         │
│                      │ (separiert von Zeal)       │
└──────────────────────────────────────────────────┘
```

**Was Studenten nicht können:**
- Docset-Pfad ändern (UI gesperrt + Code hart verdrahtet)
- Docsets aus dem Internet herunterladen (kein Netzwerkverkehr, keine Update-Features)
- Update-Prüfung auslösen (Menüpunkt entfernt, Checkbox versteckt, Code auf `false` gesetzt)
- Docset-Dateien verändern (Dateirechte `root:root 755`)
- Versehentlich die Upstream-Zeal-Konfig nutzen (separater QSettings-Namespace)

---

## 7. Sonstige neue Dateien (untracked)

| Datei | Beschreibung |
|---|---|
| `Prov_Doku.txt` | Ursprüngliche Projektdokumentation (etwas veraltet, dokumentiert Qt-5-Strategie) |
| `compressed.md` | Zusammenfassung der `video.sh`-Änderungen |
| `plan.md` | Plan-Dokument (von Reasonix generiert) |
| `praesentation.html` | HTML-Präsentationsdatei |
| `pres_vid/` | Bildschirmaufnahmen (WebM/MP4) |
| `package.json` / `package-lock.json` | Node.js-Abhängigkeiten (`kittylitter`) |
| `file` | MongoDB-Aggregation-Beispiel (projektfremd) |
| `gitignore` | `node_modules/` |
| `build_all_docsets_backup.txt` | Ältere Version von `build_all.py` (einfacher, ohne argparse/Threading) |
