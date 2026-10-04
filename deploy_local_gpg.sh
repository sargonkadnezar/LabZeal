#!/bin/bash
# deploy_local_gpg.sh
# Variante von deploy_local.sh mit signiertem APT-Repository (Proof of Concept).
# Unterschiede zur Basisvariante:
#   - generiert bei Bedarf einen GPG-Signaturschluessel (RSA 3072, automatisch)
#   - signiert die Release-Datei (Release.gpg, InRelease)
#   - schreibt die APT-Quelle mit Signed-By und ohne "Trusted: yes"
# Voraussetzung: gpg (GnuPG) sowie dpkg-scanpackages/apt-ftparchive sind installiert.
# Ueber Umgebungsvariablen ueberschreibbar (fuer Staging-Tests ohne Nginx):
#   LABZEAL_WEB_DIR, LABZEAL_KEYRING_DIR, LABZEAL_REPO_URI, LABZEAL_GPG_ID,
#   LABZEAL_SOURCES_FILE, LABZEAL_LEGACY_LIST_FILE
set -e

WEB_DIR="${LABZEAL_WEB_DIR:-/var/www/html/labzeal}"
DEBS_DIR="$WEB_DIR/debs"
BACKUP_DIR="$HOME/labzeal_backup"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_DIR="$SCRIPT_DIR/labzeal_dist"
LABZEAL_DEB_DIR="$SCRIPT_DIR/labzeal-deb"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

GPG_KEY_ID="${LABZEAL_GPG_ID:-labzeal-repo@labzeal.local}"
KEYRING_DIR="${LABZEAL_KEYRING_DIR:-/etc/apt/keyrings}"
SOURCES_FILE="${LABZEAL_SOURCES_FILE:-/etc/apt/sources.list.d/labzeal.sources}"
LEGACY_LIST_FILE="${LABZEAL_LEGACY_LIST_FILE:-/etc/apt/sources.list.d/labzeal.list}"
WEB_LABEL="${LABZEAL_REPO_URI:-http://127.0.0.1/labzeal/}"

echo "=========================================="
echo "Starte signiertes LabZeal Deployment (PoC)..."
echo "=========================================="

# 0. GPG-Signaturschluessel bereitstellen
if ! gpg --list-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
    echo "[0/5] Erzeuge neuen GPG-Signaturschluessel ($GPG_KEY_ID, RSA 3072)..."
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Key-Usage: sign
Name-Real: LabZeal Repository
Name-Email: $GPG_KEY_ID
Expire-Date: 0
%commit
EOF
else
    echo "[0/5] GPG-Signaturschluessel $GPG_KEY_ID bereits vorhanden."
fi

# 1. Backup (mit LABZEAL_SKIP_BACKUP=1 ueberspringen; das Archiv kann mehrere GB gross werden)
echo "[1/5] Erstelle Backup..."
mkdir -p "$BACKUP_DIR"

if [ "${LABZEAL_SKIP_BACKUP:-0}" = "1" ]; then
    echo "  -> Backup uebersprungen (LABZEAL_SKIP_BACKUP=1)."
elif [ -d "$DEBS_DIR" ]; then
    sudo tar -czf "$BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz" -C "$WEB_DIR" debs 2>/dev/null || true
    sudo chown $USER:$USER "$BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz"
    echo "  -> Alte Version gesichert in: $BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz"
else
    echo "  -> Noch keine alten Pakete in $DEBS_DIR vorhanden. Ueberspringe Backup."
fi

# 2. Prepare directory
echo "[2/5] Bereite Web-Verzeichnis vor..."
sudo mkdir -p "$DEBS_DIR"

# 3. Copy new packages
echo "[3/5] Kopiere neue .deb Pakete nach $DEBS_DIR..."

# Copy docset debs from labzeal_dist
if compgen -G "$LOCAL_DIR/*.deb" > /dev/null; then
    sudo cp "$LOCAL_DIR"/*.deb "$DEBS_DIR/"
else
    echo "  (keine docset .deb Dateien in $LOCAL_DIR gefunden)"
fi

# Copy labzeal core deb from labzeal-deb
if compgen -G "$LABZEAL_DEB_DIR/*.deb" > /dev/null; then
    sudo cp "$LABZEAL_DEB_DIR"/*.deb "$DEBS_DIR/"
else
    echo "  (keine labzeal .deb Dateien in $LABZEAL_DEB_DIR gefunden)"
fi

# 4. APT-Index und signierte Release-Datei erzeugen
echo "[4/5] Generiere APT-Index und signiere Release..."
cd "$WEB_DIR" || exit
sudo bash -c 'dpkg-scanpackages . /dev/null > Packages && gzip -9c Packages > Packages.gz && apt-ftparchive release . > Release'
sudo gpg --homedir "$HOME/.gnupg" --no-permission-warning --batch --yes --default-key "$GPG_KEY_ID" -abs -o Release.gpg Release
sudo gpg --homedir "$HOME/.gnupg" --no-permission-warning --batch --yes --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release

# Public Key exportieren und fuer Server und Clients bereitstellen
TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_KEY"' EXIT
gpg --armor --export "$GPG_KEY_ID" > "$TMP_KEY"
sudo install -D -m 0644 "$TMP_KEY" "$WEB_DIR/labzeal-pubkey.asc"
sudo install -D -m 0644 "$TMP_KEY" "$KEYRING_DIR/labzeal-pubkey.asc"
echo "  -> Public Key: $WEB_DIR/labzeal-pubkey.asc und $KEYRING_DIR/labzeal-pubkey.asc"

# 5. Signierte APT-Quelle eintragen und Cache aktualisieren
echo "[5/5] Aktiviere signiertes lokales APT Repository..."
if [ -f "$LEGACY_LIST_FILE" ]; then
    sudo rm -f "$LEGACY_LIST_FILE"
fi

sudo tee "$SOURCES_FILE" > /dev/null <<EOF
Types: deb
URIs: ${LABZEAL_REPO_URI:-http://127.0.0.1/labzeal/}
Suites: /
Components:
Signed-By: $KEYRING_DIR/labzeal-pubkey.asc
Enabled: yes
EOF

sudo apt-get update -qq

echo "=========================================="
echo "Fertig! Signiertes Repository live auf $WEB_LABEL"
echo "Teste es mit:"
echo "  sudo apt install labzeal-all -y"
echo "  Oder ueber Ansible: ansible-playbook ansible/deploy_labzeal.yml"
echo "=========================================="