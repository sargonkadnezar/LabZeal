# Testlauf auf einem Client-Rechner (PoC)

Kurzer Nachweis, dass die signierte Paketquelle und das Ansible-Playbook auf
einem echten Client funktionieren. Erzeugt die beiden Screenshots fuer
Abschnitt 5.4 der Arbeit.

## 0. Vorbereitung: Repository pruefen

Das Playbook installiert das Meta-Paket `labzeal-all`. Es muss im Webroot
liegen. Ein veraltetes `labzeal-demo.deb` (frueherer Paketname) wird entfernt,
damit es nicht im Index bleibt:

```bash
cd /home/alex/LabZeal
ls /var/www/html/labzeal/debs/labzeal-all.deb || python3 build_all.py --limit 3 --skip-existing
sudo rm -f /var/www/html/labzeal/debs/labzeal-demo.deb
```

## Variante A: Schnelltest mit MultiPass (empfohlen)

```bash
# 1) VM-Name und IP ermitteln
multipass list

# 2) Auf dem Host: signiertes Repository erzeugen (Nginx serviert /var/www/html)
cd /home/alex/LabZeal
bash deploy_local_gpg.sh
HOST_IP=$(hostname -I | awk '{print $1}')
ls -la /var/www/html/labzeal/          # InRelease, Release.gpg, labzeal-pubkey.asc, debs/

# 3) Erreichbarkeit aus der VM pruefen
multipass exec <vm> -- curl -sI "http://$HOST_IP/labzeal/InRelease" | head -1

# 4) Inventar anlegen
cp ansible/inventory.example.ini ansible/inventory.ini
#   labzeal-client ansible_host=<VM-IP> ansible_user=ubuntu   eintragen

# 5) Playbook gegen die VM ausfuehren
ansible-playbook -i ansible/inventory.ini ansible/deploy_labzeal.yml \
  -e labzeal_hosts=clients -e labzeal_connection=ssh \
  -e labzeal_repo_uri="http://$HOST_IP/labzeal/" \
  -e labzeal_pubkey_url="http://$HOST_IP/labzeal/labzeal-pubkey.asc"
# -> Screenshot 1: PLAY RECAP mit failed=0

# 6) Ergebnis auf der VM pruefen
multipass exec <vm> -- sudo apt-get update
multipass exec <vm> -- dpkg -l | grep labzeal
multipass exec <vm> -- ls -ld /usr/share/labzeal/docsets
# -> Screenshot 2: apt-get update ohne Signaturwarnung, Pakete auf Status ii
```

Hinweise:

* Ubuntu-Images bringen `python3` mit, das Ansible auf dem Ziel benoetigt.
* `labzeal_become` ist standardmaessig `true`; der Benutzer `ubuntu` hat
  passwortloses `sudo`, ein `-K` ist fuer die VM nicht noetig.
* Fuer den reinen Localhost-Lauf (`hosts` bleibt `localhost`) ist `-K`
  erforderlich, wenn `sudo` ein Passwort verlangt.

## Variante B: Nur auf dem Entwicklungsrechner

```bash
cd /home/alex/LabZeal
bash deploy_local_gpg.sh
ansible-playbook ansible/deploy_labzeal.yml -K
ls -l /etc/apt/keyrings/labzeal-pubkey.asc
cat /etc/apt/sources.list.d/labzeal.sources
sudo apt-get update
dpkg -l | grep labzeal
ls -ld /usr/share/labzeal/docsets
```

## Alternativer Ausrollweg (ohne Ansible)

`repo-setup/build_repo_setup.sh` erzeugt ein Bootstrap-Paket, das den
oeffentlichen Schluessel und die `.sources`-Datei enthaelt:

```bash
KEY_SRC=/var/www/html/labzeal/labzeal-pubkey.asc \
REPO_URI="http://$HOST_IP/labzeal/" \
bash repo-setup/build_repo_setup.sh ./labzeal-deb
```

Das Paket wird einmalig ueber einen bereits vertrauten Kanal installiert
(Verwaltungswerkzeug der Schule, Systemabbild oder manuell). Danach kann
`labzeal-all` ueber `apt` bezogen werden.
