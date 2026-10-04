#!/bin/bash
# Baut das Bootstrap-Paket labzeal-repo-setup (Keyring + signierte APT-Quelle).
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$SRC_DIR/../labzeal-deb}"
REPO_URI="${REPO_URI:-http://127.0.0.1/labzeal/}"
KEY_SRC="${KEY_SRC:-/var/www/html/labzeal/labzeal-pubkey.asc}"
VERSION="${VERSION:-1.0.0}"

if [ ! -f "$KEY_SRC" ]; then
    echo "Schluessel nicht gefunden: $KEY_SRC (deploy_local_gpg.sh zuerst ausfuehren)" >&2
    exit 1
fi

PKG_DIR="$(mktemp -d)"
trap 'rm -rf "$PKG_DIR"' EXIT
ROOT="$PKG_DIR/labzeal-repo-setup"
mkdir -p "$ROOT/DEBIAN" "$ROOT/etc/apt/keyrings" "$ROOT/etc/apt/sources.list.d"
cp "$KEY_SRC" "$ROOT/etc/apt/keyrings/labzeal-pubkey.asc"

cat > "$ROOT/etc/apt/sources.list.d/labzeal.sources" <<EOF
Types: deb
URIs: $REPO_URI
Suites: /
Components:
Signed-By: /etc/apt/keyrings/labzeal-pubkey.asc
Enabled: yes
EOF

cat > "$ROOT/DEBIAN/control" <<EOF
Package: labzeal-repo-setup
Version: $VERSION
Architecture: all
Section: admin
Priority: optional
Description: Richtet die signierte LabZeal-Paketquelle ein
 Installiert den oeffentlichen Schluessel des Repositories und die
 signierte APT-Quelle. Danach kann labzeal-all ueber apt bezogen werden.
EOF

cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    command -v apt-get >/dev/null 2>&1 && apt-get update -qq || true
fi
exit 0
EOF
chmod 755 "$ROOT/DEBIAN/postinst"

mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group -Zgzip -z1 --build "$ROOT" \
    "$OUT_DIR/labzeal-repo-setup_${VERSION}_all.deb"
echo "Erstellt: $OUT_DIR/labzeal-repo-setup_${VERSION}_all.deb"
