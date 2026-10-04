import os
import requests
import tarfile
import subprocess
import shutil
import re
import sqlite3
import base64
import time
import argparse
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

API_URL = "https://api.zealdocs.org/v1/docsets"
BASE_DIR = os.path.abspath("./labzeal_dist")

META_PACKAGE_NAME = "labzeal-all"
MAINTAINER = "Alexander Tieber <jungewas40@gmail.com>"


def sanitize_package_name(name):
    """Leitet den Debian-Paketnamen eines Docsets aus dem API-Namen ab."""
    safe_name = re.sub(r'[^a-z0-9\-+.]', '', name.lower().replace('_', '-'))
    return f"labzeal-docset-{safe_name}"


def build_control_content(pkg_name, title):
    """Erzeugt den Inhalt der DEBIAN/control-Datei eines Docset-Pakets."""
    return f"""Package: {pkg_name}
Version: 1.0.0
Architecture: all
Maintainer: {MAINTAINER}
Depends: labzeal
Section: doc
Priority: optional
Homepage: https://zealdocs.org/
Description: LabZeal with the {title} Docset included already.
 Offline API documentation for LabZeal.
"""


def filter_latest_versions(docsets):
    """Behaelt je Docset nur die hoechste Version und filtert Nicht-Kapeli-Docsets
    sowie 'user contributed'- und 'cheatsheet'-Eintraege aus."""
    filtered_docsets = {}
    for ds in docsets:
        title = ds['title']
        name = ds['name']
        if ds.get('sourceId', 'com.kapeli') != 'com.kapeli':
            continue
        if "user contributed" in title.lower() or "cheatsheet" in title.lower():
            continue
        if name.endswith("_contrib") or name.endswith("_cheatsheet"):
            continue

        match = re.match(r'^(.*?)\s*([0-9]+(?:\.[0-9]+)*)$', title)
        if match:
            base_name = match.group(1).strip()
            version_tuple = tuple(map(int, match.group(2).split('.')))
            if base_name in filtered_docsets:
                if version_tuple > filtered_docsets[base_name].get('_parsed_version', (0,)):
                    ds['_parsed_version'] = version_tuple
                    filtered_docsets[base_name] = ds
            else:
                ds['_parsed_version'] = version_tuple
                filtered_docsets[base_name] = ds
        else:
            filtered_docsets[title] = ds
    return list(filtered_docsets.values())



def ensure_docset_icons(docset_dir, icon_url, icon2x_url):
    def save_icon_from_source(source, target_path):
        if not source:
            return
        if source.startswith(('http://', 'https://')):
            try:
                r = requests.get(source, timeout=10)
                if r.status_code == 200:
                    with open(target_path, "wb") as f:
                        f.write(r.content)
                else:
                    print(f"     [Warning] Icon download status {r.status_code}")
            except Exception as e:
                print(f"     [Error] Icon download: {e}")
        else:
            try:
                if source.startswith("data:"):
                    base64_data = source.split(",", 1)[1]
                else:
                    base64_data = source
                img_data = base64.b64decode(base64_data)
                with open(target_path, "wb") as f:
                    f.write(img_data)
                print(f"     [OK] Icon decoded from Base64")
            except Exception as e:
                print(f"     [Error] Base64 decode: {e}")

    icon_path = os.path.join(docset_dir, "icon.png")
    icon2x_path = os.path.join(docset_dir, "icon@2x.png")

    if not os.path.exists(icon_path):
        print(f"  -> Loading icon for {os.path.basename(docset_dir)}")
        save_icon_from_source(icon_url, icon_path)

    if not os.path.exists(icon2x_path):
        save_icon_from_source(icon2x_url, icon2x_path)


def build_docset_index(docset_dir):
    dsidx_path = os.path.join(docset_dir, "Contents", "Resources", "docSet.dsidx")
    documents_dir = os.path.join(docset_dir, "Contents", "Resources", "Documents")
    if not os.path.exists(dsidx_path) or not os.path.isdir(documents_dir):
        return

    with sqlite3.connect(dsidx_path) as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS searchIndex(
                id INTEGER PRIMARY KEY,
                name TEXT,
                type TEXT,
                path TEXT
            );
        """)
        cursor.execute("PRAGMA journal_mode=DELETE;")
        count = 0
        title_pattern = re.compile(r'<title>(.*?)</title>', re.IGNORECASE | re.DOTALL)
        READ_SIZE = 2048

        for root, dirs, files in os.walk(documents_dir):
            for file in files:
                if not file.endswith('.html'):
                    continue
                html_path = os.path.join(root, file)
                rel_path = os.path.relpath(html_path, documents_dir)
                title = os.path.splitext(file)[0]
                try:
                    with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
                        head = f.read(READ_SIZE)
                        match = title_pattern.search(head)
                        if match:
                            title = match.group(1).strip()
                        else:
                            f.seek(0)
                            full = f.read()
                            match = title_pattern.search(full)
                            if match:
                                title = match.group(1).strip()
                except:
                    pass
                cursor.execute(
                    "INSERT OR IGNORE INTO searchIndex (name, type, path) VALUES (?, ?, ?)",
                    (title, "Guide", rel_path)
                )
                count += 1
        conn.commit()
    print(f"  [OK] Indexed {count} entries for {os.path.basename(docset_dir)}")


def create_debian_package(name, title, download_url, icon_url, icon2x_url, skip_existing=False):
    t_start = time.time()

    pkg_name = sanitize_package_name(name)
    deb_path = os.path.join(BASE_DIR, f"{pkg_name}.deb")

    if skip_existing and os.path.exists(deb_path):
        print(f"  Skipping {title} - {pkg_name}.deb already exists")
        return pkg_name

    t_dl = t_index = t_deb = 0.0

    tmp_dir = tempfile.mkdtemp(prefix="labzeal_build_", dir=BASE_DIR)
    try:
        pkg_dir = os.path.join(tmp_dir, pkg_name)
        docset_dest = os.path.join(pkg_dir, "usr/share/labzeal/docsets")
        debian_dir = os.path.join(pkg_dir, "DEBIAN")
        os.makedirs(docset_dest, exist_ok=True)
        os.makedirs(debian_dir, exist_ok=True)

        print(f"Downloading {title}...")
        try:
            response = requests.get(download_url, stream=True, timeout=30)
            response.raise_for_status()

            # Stream to a temp file inside tmp_dir so finally block cleans it up
            with tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz', dir=tmp_dir) as tmp_f:
                tmp_archive = tmp_f.name
                for chunk in response.iter_content(chunk_size=65536):
                    if chunk:
                        tmp_f.write(chunk)

            # Verify gzip magic bytes on the file
            with open(tmp_archive, 'rb') as f:
                header = f.read(2)
            if not header or header != b'\x1f\x8b':
                print(f"  [WARNING] {title} is not a gzip archive, skipping.")
                os.unlink(tmp_archive)
                return None

            with tarfile.open(tmp_archive, mode="r:gz") as tar:
                if hasattr(tarfile, 'data_filter'):
                    tar.extractall(path=docset_dest, filter='data')
                else:
                    tar.extractall(path=docset_dest)

            os.unlink(tmp_archive)
            t_dl = time.time()

        except Exception as e:
            print(f"  [ERROR] Could not download {title}: {e}")
            return None

        # Icons + index in one pass
        for folder in os.listdir(docset_dest):
            docset_folder = os.path.join(docset_dest, folder)
            if os.path.isdir(docset_folder) and folder.endswith('.docset'):
                ensure_docset_icons(docset_folder, icon_url, icon2x_url)
                build_docset_index(docset_folder)

        t_index = time.time()

        control_content = build_control_content(pkg_name, title)
        with open(os.path.join(debian_dir, "control"), "w") as f:
            f.write(control_content)

        # --root-owner-group forces all files in the .deb to root:root,
        # regardless of the build user.  This ensures docsets are immutable
        # after installation — the parent /usr/share/labzeal/docsets is already
        # owned by root, and the app's isDirWritable() check disables all
        # modify controls when the storage path is not user-writable.
        subprocess.run(["dpkg-deb", "--root-owner-group", "-Zgzip", "-z1", "--build", pkg_dir],
                       stdout=subprocess.DEVNULL)
        t_deb = time.time()
        shutil.move(f"{pkg_dir}.deb", deb_path)

        print(f"  [TIMING] {title}: Download: {t_dl - t_start:.1f}s | Index: {t_index - t_dl:.1f}s | Deb build: {t_deb - t_index:.1f}s")
        return pkg_name

    finally:
        shutil.rmtree(tmp_dir)


def build_meta_package(package_list):
    print(f"\nBuilding meta-package '{META_PACKAGE_NAME}'...")
    meta_pkg_name = META_PACKAGE_NAME
    tmp_dir = tempfile.mkdtemp(prefix="labzeal_meta_", dir=BASE_DIR)
    try:
        meta_dir = os.path.join(tmp_dir, meta_pkg_name)
        debian_dir = os.path.join(meta_dir, "DEBIAN")
        os.makedirs(debian_dir, exist_ok=True)
        depends_str = ", ".join(package_list)

        control_content = f"""Package: {meta_pkg_name}
Version: 1.0.0
Section: metapackages
Priority: optional
Architecture: all
Depends: {depends_str}
Maintainer: Alexander Tieber <jungewas40@gmail.com>
Description: Installiert ein Set an LabZeal Docsets
 Meta-Paket, das eine auswählbare Anzahl an Docsets lädt.
"""
        with open(os.path.join(debian_dir, "control"), "w") as f:
            f.write(control_content)

        subprocess.run(["dpkg-deb", "--root-owner-group", "-Zgzip", "-z1", "--build", meta_dir],
                       stdout=subprocess.DEVNULL)
        shutil.move(f"{meta_dir}.deb", os.path.join(BASE_DIR, f"{meta_pkg_name}.deb"))
        print("Meta-package ready!")
    finally:
        shutil.rmtree(tmp_dir)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Baue LabZeal Docset-Pakete")
    parser.add_argument("--limit", type=int, default=12, help="Anzahl Docsets (default: 12)")
    parser.add_argument("--workers", type=int, default=0, help="Threads (default: min(8, CPU cores))")
    parser.add_argument("--deploy", action="store_true", help="deploy_local.sh am Ende ausführen")
    parser.add_argument("--output", default="./labzeal_dist", help="Ausgabeverzeichnis (default: ./labzeal_dist)")
    parser.add_argument("--skip-existing", action="store_true", help="Bereits gebaute .deb überspringen")
    args = parser.parse_args()

    BASE_DIR = os.path.abspath(args.output)
    os.makedirs(BASE_DIR, exist_ok=True)

    max_workers = args.workers if args.workers > 0 else min(8, (os.cpu_count() or 4))

    print("Fetching docset list from API...")
    r = requests.get(API_URL)
    docsets = r.json()

    docsets_to_build = filter_latest_versions(docsets)[:args.limit]
    print(f"\n--> Filtered! Building demo set with {len(docsets_to_build)} packages ({max_workers} workers)...\n")

    t_total_start = time.time()
    successful_packages = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(
                create_debian_package,
                ds['name'], ds['title'],
                f"https://go.zealdocs.org/d/com.kapeli/{ds['name']}/latest",
                ds.get('icon', ''), ds.get('icon2x', ''),
                args.skip_existing
            ): ds
            for ds in docsets_to_build
        }
        total = len(futures)
        for idx, future in enumerate(as_completed(futures), 1):
            pkg_name = future.result()
            if pkg_name:
                successful_packages.append(pkg_name)
            print(f"  [Progress] {idx}/{total}")

    if successful_packages:
        build_meta_package(successful_packages)

    t_total_end = time.time()
    print(f"\nDone! All packages are in {BASE_DIR}")
    print(f"  [TIMING] Total time: {t_total_end - t_total_start:.1f}s")

    if args.deploy:
        print("\n--> Running deploy_local.sh ...")
        subprocess.run(["bash", "./deploy_local.sh"])
