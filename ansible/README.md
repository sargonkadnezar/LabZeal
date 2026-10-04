# LabZeal Deployment mit GPG-Signatur und Ansible (Proof of Concept)

Dieses Verzeichnis enthält die PoC-Variante des LabZeal-Deployments. Sie
erweitert das bestehende Konzept (Bash-Skripte + APT-Repository) um zwei
Komponenten, ohne dessen Architektur zu verändern:

1. **Signiertes APT-Repository** (`deploy_local_gpg.sh`): Die `Release`-Datei
   wird mit einem GPG-Schlüssel signiert (`Release.gpg`, `InRelease`). Die
   Client-Quelle verweist per `Signed-By` auf den öffentlichen Schlüssel,
   `Trusted: yes` entfällt. APT verifiziert damit Authentizität und
   Unversehrtheit der Pakete.
2. **Ansible-Playbook** (`deploy_labzeal.yml`): Richtet einen Client zustands-
   basiert ein (Schlüssel, Quelle, Installation). Im Schulnetzwerk ersetzt
   dieses Playbook die manuelle Einrichtung der Client-Rechner.

## Ablauf

Voraussetzungen: `gpg`, `dpkg-scanpackages`, `apt-ftparchive`, `ansible-core`
(`sudo apt install gnupg dpkg-dev ansible-core`).

Server-Seite (einmalig, danach bei jedem Update):

```bash
bash deploy_local_gpg.sh
```

Der GPG-Signaturschlüssel (`labzeal-repo@labzeal.local`, RSA 3072, ohne
Ablauf) wird automatisch erzeugt, falls er nicht existiert. Der öffentliche
Schlüssel landet in `/var/www/html/labzeal/labzeal-pubkey.asc` und
`/etc/apt/keyrings/labzeal-pubkey.asc`.

Client-Seite (PoC: lokaler Rechner):

```bash
ansible-playbook ansible/deploy_labzeal.yml
```

Gebündelt über die Pipeline (Cleanup → Build → signiertes Deployment →
Ansible-Installation):

```bash
bash pipeline_ansible.sh --install
```

## Vergleich der Varianten

| | ohne Signatur/Ansible | mit Signatur/Ansible (PoC) |
|---|---|---|
| Repository | `deploy_local.sh`, `Trusted: yes` | `deploy_local_gpg.sh`, `Release.gpg` + `InRelease`, `Signed-By` |
| Installation | `sudo apt install labzeal-all -y` | `ansible-playbook ansible/deploy_labzeal.yml` |
| Pipeline | `pipeline.sh [--install]` | `pipeline_ansible.sh [--install]` |
| Cleanup | `cleanup.sh` (für beide Varianten) | `cleanup.sh` |

## Schulnetzwerk

Für den produktiven Einsatz sind im Playbook die Loopback-Adresse durch die
statische IP des Servers und `hosts: localhost` durch die Inventargruppe der
Client-Rechner zu ersetzen. Der GPG-Schlüssel bleibt auf dem Server; die
Clients benötigen ausschließlich den öffentlichen Teil.

## Verifiziert (End-to-End-Test)

`ansible/poc_test.sh` führt den PoC vollständig aus (rootless, schreibt nur in
`/tmp`): Es baut Testpakete (`labzeal`, `labzeal-docset-python-3`,
`labzeal-all`), führt das echte Skript `deploy_local_gpg.sh` gegen ein
Staging-Verzeichnis aus (sudo-Stub + `LABZEAL_*`-Variablen), prüft die
Client-Seite mit umgeleiteten apt-Verzeichnissen gegen ein signiertes
`file://`-Repository und führt die Manipulations- sowie Signaturtests und das
Ansible-Playbook aus.

Reproduzieren:

```bash
bash ansible/poc_test.sh
```

Letzter Lauf (Log: `poc_test.log`): 16 Prüfungen, 0 Fehlschläge.

| Prüfung | Ergebnis |
|---|---|
| `deploy_local_gpg.sh` läuft vollständig durch (`InRelease`, `Release.gpg`, `Packages.gz`, Public Key) | OK |
| `apt-get update` akzeptiert das signierte Repository (`InRelease` wird heruntergeladen) | OK |
| `apt-get install --download-only labzeal-all` löst `labzeal` + Docset-Paket auf und lädt sie | OK |
| Manipulierte Paketliste wird abgewiesen (Hash Sum mismatch) | OK |
| Unsigniertes Repository wird abgewiesen (is not signed) | OK |
| Falscher Public Key wird abgewiesen (NO_PUBKEY, `Signed-By` wirkt) | OK |
| `gpg --verify InRelease` (Good signature) | OK |
| Playbook `--syntax-check` + Tasks `key,source` (ok=4, changed=2) | OK |

Die apt-Schritte des Playbooks (`install`-Tag, `update_cache` und Installation
des Meta-Pakets) benötigen root und laufen auf dem Entwicklungsrechner über
`sudo apt install ansible-core` und `ansible-playbook ansible/deploy_labzeal.yml`.
Die zugrunde liegenden apt-Operationen entsprechen den oben geprüften
(Update und Install gegen das signierte Repository). Das Playbook ist über
die Variable `labzeal_become` (default `true`) steuerbar; für rootless Tests
wird `-e labzeal_become=false` gesetzt.