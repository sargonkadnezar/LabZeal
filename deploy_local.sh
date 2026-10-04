#!/bin/bash
set -e

WEB_DIR="/var/www/html/labzeal"
DEBS_DIR="$WEB_DIR/debs"
BACKUP_DIR="$HOME/labzeal_backup"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_DIR="$SCRIPT_DIR/labzeal_dist"
LABZEAL_DEB_DIR="$SCRIPT_DIR/labzeal-deb"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "=========================================="
echo "Starte lokales LabZeal Deployment..."
echo "=========================================="

# 1. Backup
echo "[1/4] Erstelle Backup..."
mkdir -p "$BACKUP_DIR"

if [ -d "$DEBS_DIR" ]; then
    sudo tar -czf "$BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz" -C "$WEB_DIR" debs 2>/dev/null || true
    sudo chown $USER:$USER "$BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz"
    echo "  -> Alte Version gesichert in: $BACKUP_DIR/labzeal_debs_$TIMESTAMP.tar.gz"
else
    echo "  -> Noch keine alten Pakete in $DEBS_DIR vorhanden. Ueberspringe Backup."
fi

# 2. Prepare directory
echo "[2/4] Bereite Web-Verzeichnis vor..."
sudo mkdir -p "$DEBS_DIR"

# 3. Copy new packages
echo "[3/4] Kopiere neue .deb Pakete nach $DEBS_DIR..."

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

# 4. Regenerate APT index
echo "[4/4] Generiere Packages.gz (APT Index)..."
cd "$WEB_DIR" || exit
sudo rm -f Packages Packages.gz
sudo bash -c 'dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz'

# 5. Create APT source entry and refresh cache
echo "[5/5] Aktiviere lokales APT Repository..."
if [ -f /etc/apt/sources.list.d/labzeal.list ]; then
    sudo rm -f /etc/apt/sources.list.d/labzeal.list
fi

sudo tee /etc/apt/sources.list.d/labzeal.sources > /dev/null <<EOF
Types: deb
URIs: http://127.0.0.1/labzeal/
Suites: /
Components:
Trusted: yes
Enabled: yes
EOF

sudo apt-get update -qq

echo "=========================================="
echo "Fertig! Die Pakete sind live auf http://127.0.0.1/labzeal"
echo "Teste es mit:"
echo "  sudo apt install labzeal-all -y"
echo "=========================================="
