# Bootstrap-Paket `labzeal-repo-setup`

Ergaenzt das Ansible-Playbook um einen zweiten Weg, die signierte Paketquelle
auf den Clients bekannt zu machen. Statt per SSH/Ansible wird ein kleines
Debian-Paket ueber einen bereits vertrauten Kanal ausgerollt
(Verwaltungswerkzeug der Schule, Systemabbild oder manuelle Installation).

Das Paket enthaelt:

* `/etc/apt/keyrings/labzeal-pubkey.asc` - oeffentlicher Schluessel des Repositories
* `/etc/apt/sources.list.d/labzeal.sources` - signierte Quelle (`Signed-By`)

Das `postinst`-Skript fuehrt einmalig `apt-get update` aus. Danach kann
`labzeal-all` ueber `apt` bezogen werden. Bei einem Schluesselwechsel muss das
Bootstrap-Paket erneut ausgerollt werden.

## Bauen

```bash
KEY_SRC=/var/www/html/labzeal/labzeal-pubkey.asc \
REPO_URI=http://127.0.0.1/labzeal/ \
bash repo-setup/build_repo_setup.sh ./labzeal-deb
```

Ohne Argument wird `../labzeal-deb` als Ausgabeverzeichnis verwendet.
