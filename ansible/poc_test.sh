#!/bin/bash
# poc_test.sh — Rootless End-to-End-Verifikation des signierten LabZeal-Repos
# und des Ansible-Playbooks (Proof of Concept).
#
# Fuehrt den Server-Teil (das echte Skript deploy_local_gpg.sh), die Client-Seite
# (apt mit Signed-By, Signatur- und Hash-Pruefung) und das Ansible-Playbook mit
# umgeleiteten Pfaden aus, ohne root:
#   - deploy_local_gpg.sh laeuft ueber LABZEAL_*-Umgebungsvariablen gegen ein
#     Staging-Verzeichnis; ein sudo-Stub ersetzt die Rechteerhoehung.
#   - apt laeuft mit umgeleiteten Verzeichnissen (-o Dir::...) gegen ein
#     file://-Repository; die Nginx-Schicht ist dabei ersetzt.
#
# Auf dem Entwicklungsrechner mit root/Nginx die Skripte direkt ausfuehren:
#   bash deploy_local_gpg.sh
#   ansible-playbook ansible/deploy_labzeal.yml
#
# Ausfuehrung: bash ansible/poc_test.sh   (schreibt nur nach /tmp)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /tmp/labzeal-poc.XXXXXX)"
LOG="$T/poc_test.log"
exec > >(tee "$LOG") 2>&1
echo "==> PoC-Testroot : $T"
echo "==> Repo-Root    : $REPO_ROOT"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- Umgebung: isoliertes HOME/GNUPGHOME, sudo-Stub, apt-Umleitung ----------
export HOME="$T/home"; mkdir -p "$HOME"
export GNUPGHOME="$HOME/.gnupg"; mkdir -m 700 "$GNUPGHOME"
mkdir -p "$T/bin" "$T/client-key" "$T/base"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
# Test-Stub: fuehrt das Kommando ohne Rechteerhoehung aus.
case "$1" in
  chown) exit 0 ;;   # Dateien gehoeren dem Testnutzer bereits
  *) exec "$@" ;;
esac
EOF
chmod +x "$T/bin/sudo"
export PATH="$T/bin:$PATH"

APT_CONF="$T/apt.conf"
mkdir -p "$T/base/lists" "$T/base/state" "$T/base/archives" "$T/sparts" "$T/dpkg"
cp /var/lib/dpkg/status "$T/dpkg/status" 2>/dev/null || touch "$T/dpkg/status"
cat > "$APT_CONF" <<EOF
Dir::Etc::sourcelist "/dev/null";
Dir::Etc::sourceparts "$T/sparts";
Dir::State "$T/base/state";
Dir::State::lists "$T/base/lists";
Dir::State::status "$T/dpkg/status";
Dir::Cache "$T/base/archives";
Dir::Cache::archives "$T/base/archives";
APT::Get::List-Cleanup "0";
EOF

# apt mit frischem Zustand pro Test (ortsunabhaengige, rootless Umleitung)
aptu() { # $1 = Testname (erzeugt eigene lists/state)
  local L="$T/$1"
  mkdir -p "$L/lists" "$L/state"
  apt-get -o APT::Color=0 -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$T/sparts" \
    -o Dir::State="$L/state" -o Dir::State::lists="$L/lists" -o Dir::State::status="$T/dpkg/status" \
    -o Dir::Cache="$L/state" -o Dir::Cache::archives="$L/state/archives" update
}
apt_install() { # $1 = Testname (dessen lists zuvor via aptu gefuellt wurden), $2 = Paket
  local L="$T/$1"
  mkdir -p "$L/archives"
  apt-get -o APT::Color=0 -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$T/sparts" \
    -o Dir::State="$L/state" -o Dir::State::lists="$L/lists" -o Dir::State::status="$T/dpkg/status" \
    -o Dir::Cache="$L/archives" -o Dir::Cache::archives="$L/archives" install --download-only -y "$2"
}
aptu_alt() { # $1 = Testname, $2 = sourceparts-Dir (frischer Zustand, andere Quelle)
  local L="$T/$1"
  mkdir -p "$L/lists" "$L/state"
  apt-get -o APT::Color=0 -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$2" \
    -o Dir::State="$L/state" -o Dir::State::lists="$L/lists" -o Dir::State::status="$T/dpkg/status" \
    -o Dir::Cache="$L/state" -o Dir::Cache::archives="$L/state/archives" update
}

# --- Test-Pakete bauen (dpkg-deb --root-owner-group, wie build_all.py) ------
echo "==> Test-Pakete bauen..."
REPODIR="$T/repo"
mkdir -p "$REPODIR/labzeal_dist" "$REPODIR/labzeal-deb"

build_deb() { # name version depends arch contentpfad outdir
  local name=$1 ver=$2 deps=$3 arch=$4 content=$5 out=$6
  local d="$T/build/${name}_${RANDOM}"
  mkdir -p "$d/DEBIAN" "$d$content"
  {
    echo "Package: $name"
    echo "Version: $ver"
    echo "Architecture: $arch"
    echo "Maintainer: LabZeal PoC <test@labzeal.local>"
    [ -n "$deps" ] && echo "Depends: $deps"
    echo "Section: misc"
    echo "Priority: optional"
    echo "Description: $name (PoC-Testpaket)"
  } > "$d/DEBIAN/control"
  dpkg-deb --root-owner-group -Zgzip -z1 --build "$d" "${out}/${name}_${ver}_${arch}.deb" >/dev/null
}
build_deb labzeal 1.0.0 "" amd64 "/usr/share/labzeal/docsets" "$REPODIR/labzeal-deb"
build_deb labzeal-docset-python-3 1.0.0 "labzeal" amd64 "/usr/share/labzeal/docsets/Python.docset" "$REPODIR/labzeal_dist"
build_deb labzeal-all 1.0.0 "labzeal, labzeal-docset-python-3" all "" "$REPODIR/labzeal_dist"
echo "     $(ls "$REPODIR/labzeal-deb")"
echo "     $(ls "$REPODIR/labzeal_dist")"

# --- Server-Teil: das ECHTE deploy_local_gpg.sh (Staging-Pfade, sudo-Stub) --
echo ""
echo "==> deploy_local_gpg.sh (echtes Skript, Staging-Pfade, sudo-Stub)..."
cp "$REPO_ROOT/deploy_local_gpg.sh" "$REPODIR/deploy_local_gpg.sh"
chmod +x "$REPODIR/deploy_local_gpg.sh"
export LABZEAL_WEB_DIR="$T/www"
export LABZEAL_KEYRING_DIR="$T/keyrings"
export LABZEAL_REPO_URI="file:$T/www/"
export LABZEAL_SOURCES_FILE="$T/sparts/labzeal.sources"
export LABZEAL_LEGACY_LIST_FILE="$T/sparts/labzeal.list"
export APT_CONFIG="$APT_CONF"
if bash "$REPODIR/deploy_local_gpg.sh" >"$T/deploy.out" 2>&1; then
  ok "deploy_local_gpg.sh laeuft vollstaendig durch"
else
  bad "deploy_local_gpg.sh (Log: $T/deploy.out)"
fi
tail -8 "$T/deploy.out" | sed 's/^/     /'

echo "--- Repo-Inhalt:"
ls -1 "$T/www" | sed 's/^/     /'
echo "--- Client-Quelle ($LABZEAL_SOURCES_FILE):"
cat "$T/sparts/labzeal.sources" | sed 's/^/     /'

[ -f "$T/www/InRelease" ]   && ok "InRelease vorhanden"   || bad "InRelease fehlt"
[ -f "$T/www/Release.gpg" ] && ok "Release.gpg vorhanden" || bad "Release.gpg fehlt"
[ -f "$T/www/Packages.gz" ] && ok "Packages.gz vorhanden" || bad "Packages.gz fehlt"
[ -f "$T/keyrings/labzeal-pubkey.asc" ] && ok "Public Key im Keyring" || bad "Public Key fehlt"
grep -q "Trusted: yes" "$T/sparts/labzeal.sources" && bad "sources enthaelt Trusted: yes" || ok "kein 'Trusted: yes' in sources"

# --- Client-Seite: Signaturpruefung und Installation (rootless apt) ---------
echo ""
echo "==> Client-Seite: apt gegen signiertes file://-Repo..."
if aptu t1 >"$T/t1.out" 2>&1; then
  ok "T1: apt-get update akzeptiert signiertes Repo"
  grep -m1 "InRelease" "$T/t1.out" | sed 's/^/     /'
else
  bad "T1: apt-get update"
  tail -4 "$T/t1.out" | sed 's/^/     /'
fi

if apt_install t1 labzeal-all >"$T/t2.out" 2>&1; then
  ok "T2: labzeal-all mit Abhaengigkeiten (labzeal, docset) aufloesbar und geladen"
  grep -E "already newest|Download|Get:|upgraded" "$T/t2.out" | head -3 | sed 's/^/     /'
else
  bad "T2: labzeal-all Installation"
  tail -4 "$T/t2.out" | sed 's/^/     /'
fi
ls -1 "$T/t2/archives" 2>/dev/null | sed 's/^/     /'

# --- Manipulations- und Signaturtests ---------------------------------------
echo ""
echo "==> Manipulations- und Signaturtests..."
# T3: Paket manipulieren, Packages neu bauen, NICHT neu signieren
printf 'PWNED\n' >> "$T/www/debs/labzeal_1.0.0_amd64.deb"
( cd "$T/www" && dpkg-scanpackages . /dev/null > Packages && gzip -9c Packages > Packages.gz )
if ! aptu t3 >"$T/t3.out" 2>&1; then
  ok "T3: manipulierte Paketliste wird abgewiesen (Hash-Mismatch)"
  grep -iE "hash sum mismatch|mismatch" "$T/t3.out" | head -2 | sed 's/^/     /'
else
  bad "T3: Manipulation nicht erkannt"
fi

# T4: Signaturdateien entfernen (nur unsignierte Release uebrig)
rm -f "$T/www/InRelease" "$T/www/Release.gpg"
if ! aptu t4 >"$T/t4.out" 2>&1; then
  ok "T4: unsigniertes Repo wird abgewiesen"
  grep -iE "not signed|signature" "$T/t4.out" | head -2 | sed 's/^/     /'
else
  bad "T4: unsigniertes Repo akzeptiert"
fi

# Repo reparieren (neu signieren), fuer T5/T6
( cd "$T/www" \
    && dpkg-scanpackages . /dev/null > Packages \
    && gzip -9c Packages > Packages.gz \
    && apt-ftparchive release . > Release \
    && gpg --batch --yes --default-key labzeal-repo@labzeal.local -abs -o Release.gpg Release 2>/dev/null \
    && gpg --batch --yes --default-key labzeal-repo@labzeal.local --clearsign -o InRelease Release 2>/dev/null )

# T5: falscher Public Key in Signed-By -> Abweisung
GNUPGHOME2="$T/gnupg2"; mkdir -m 700 "$GNUPGHOME2"
GNUPGHOME="$GNUPGHOME2" gpg --batch --gen-key >/dev/null 2>&1 <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 3072
Key-Usage: sign
Name-Real: Wrong Key
Name-Email: wrong@labzeal.local
Expire-Date: 0
%commit
EOF
mkdir -p "$T/sparts2"
GNUPGHOME="$GNUPGHOME2" gpg --armor --export wrong@labzeal.local > "$T/sparts2/wrong-pubkey.asc"
sed "s|Signed-By: .*|Signed-By: $T/sparts2/wrong-pubkey.asc|" "$T/sparts/labzeal.sources" > "$T/sparts2/labzeal.sources"
if ! aptu_alt t5 "$T/sparts2" >"$T/t5.out" 2>&1; then
  ok "T5: falscher Public Key wird abgewiesen (Signed-By wirkt)"
  grep -iE "not signed|NO_PUBKEY|signature" "$T/t5.out" | head -2 | sed 's/^/     /'
else
  bad "T5: falscher Public Key akzeptiert"
fi

# T6: echte Verifikation wie ein Client (Public Key importieren, InRelease pruefen)
gpg --import "$T/www/labzeal-pubkey.asc" >/dev/null 2>&1
if gpg --verify "$T/www/InRelease" >"$T/t6.out" 2>&1; then
  ok "T6: gpg --verify InRelease (Good signature)"
  grep "Good signature" "$T/t6.out" | sed 's/^/     /'
else
  bad "T6: gpg --verify InRelease"
fi

# --- Ansible-Playbook --------------------------------------------------------
echo ""
echo "==> Ansible-Playbook (ansible-core in venv)..."
AV="$T/ansible-venv"
python3 -m venv "$AV" >/dev/null 2>&1
"$AV/bin/pip" install -q ansible-core 2>&1 | tail -1
export HOME="$T/ahome"; mkdir -p "$HOME"
export ANSIBLE_REMOTE_TMP="$T/ansible-remote-tmp"
export ANSIBLE_LOCAL_TMP="$T/ansible-local-tmp"
mkdir -p "$ANSIBLE_REMOTE_TMP" "$ANSIBLE_LOCAL_TMP"
APB="$REPO_ROOT/ansible/deploy_labzeal.yml"

if "$AV/bin/ansible-playbook" --syntax-check "$APB" >/dev/null 2>&1; then
  ok "T7: ansible-playbook --syntax-check"
else
  bad "T7: syntax-check"
fi

"$AV/bin/ansible-playbook" "$APB" --tags key,source \
  -e "labzeal_become=false" \
  -e "labzeal_repo_uri=file:$T/www/" \
  -e "labzeal_pubkey_url=file:$T/www/labzeal-pubkey.asc" \
  -e "labzeal_pubkey_path=$T/client-key/labzeal-pubkey.asc" \
  -e "labzeal_sources_path=$T/sparts/ansible.sources" \
  >"$T/t8.out" 2>&1
tail -3 "$T/t8.out" | sed 's/^/     /'
[ -f "$T/client-key/labzeal-pubkey.asc" ] && ok "T8a: Playbook legt Public Key ab" || bad "T8a: Public Key fehlt"
grep -q "Signed-By: $T/client-key/labzeal-pubkey.asc" "$T/sparts/ansible.sources" \
  && ok "T8b: Playbook schreibt signierte Quelle (Signed-By)" || bad "T8b: sources falsch"
grep -q "Trusted: yes" "$T/sparts/ansible.sources" \
  && bad "T8c: Playbook-Quelle enthaelt Trusted: yes" || ok "T8c: keine Trusted-yes-Quelle"

echo ""
echo "=========================================="
echo "Ergebnis: PASS=$PASS FAIL=$FAIL"
echo "Log: $LOG"
[ "$FAIL" -eq 0 ]