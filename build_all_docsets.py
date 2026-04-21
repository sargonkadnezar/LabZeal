import os
import requests
import tarfile
import io
import subprocess
import shutil
import re

API_URL = "https://api.zealdocs.org/v1/docsets"
BASE_DIR = os.path.abspath("./labzeal_dist")

def create_debian_package(name, title, download_url):
    safe_name = re.sub(r'[^a-z0-9\-+.]', '', name.lower().replace('_', '-'))
    pkg_name = f"labzeal-docset-{safe_name}"
    
    pkg_dir = os.path.join(BASE_DIR, "build", pkg_name)
    docset_dest = os.path.join(pkg_dir, "usr/share/labzeal/docsets")
    debian_dir = os.path.join(pkg_dir, "DEBIAN")

    os.makedirs(docset_dest, exist_ok=True)
    os.makedirs(debian_dir, exist_ok=True)

    print(f"Lade {title} herunter...")
    try:
        response = requests.get(download_url, stream=True)
        response.raise_for_status()
        with tarfile.open(fileobj=io.BytesIO(response.content), mode="r:gz") as tar:
            tar.extractall(path=docset_dest, filter='data')
    except Exception as e:
        print(f"  [FEHLER] Konnte {title} nicht laden: {e}")
        return None

    control_content = f"""Package: {pkg_name}
Version: 1.0.0
Architecture: all
Maintainer: Alexander Tieber <jungewas40@gmail.com>
Depends: labzeal
Section: doc
Priority: optional
Homepage: https://zealdocs.org/
Description: LabZeal with the {title} Docset included already.
 Zeal is a simple offline API documentation browser inspired by Dash (OS X
 app), available for Linux and Windows.
 .
  * Quickly search documentation using Alt+Space (or customised) hotkey to
    display Zeal from any place in your workspace.
  * Search in multiple sets of documentation at once.
  * Don't be dependent on your internet connection.
  * Integrate Zeal with Emacs, Sublime Text, or Vim.
LabZeal-Maintainer: Alexander Tieber <jungewas40@gmail.com>
Original-Maintainer: ChangZhuo Chen (陳昌倬) <czchen@debian.org>
"""
    with open(os.path.join(debian_dir, "control"), "w") as f:
        f.write(control_content)

    postinst_content = """#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    chown -R root:root /usr/share/labzeal/docsets/
    chmod -R a+rX /usr/share/labzeal/docsets/
fi
exit 0
"""
    postinst_path = os.path.join(debian_dir, "postinst")
    with open(postinst_path, "w") as f:
        f.write(postinst_content)
    os.chmod(postinst_path, 0o755)

    print(f"Baue Debian-Paket für {title}...")
    subprocess.run(["fakeroot", "dpkg-deb", "--build", pkg_dir], stdout=subprocess.DEVNULL)
    
    shutil.move(f"{pkg_dir}.deb", os.path.join(BASE_DIR, f"{pkg_name}.deb"))
    
    return pkg_name

def build_meta_package(package_list):
    print("\nBaue Meta-Paket 'labzeal-all'...")
    meta_pkg_name = "labzeal-all"
    meta_dir = os.path.join(BASE_DIR, "build", meta_pkg_name)
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
Description: Installiert ALLE LabZeal Docsets
 Meta-Paket, das alle offiziellen, aktuellen Sprachen in den Shared-Path laedt.
"""
    with open(os.path.join(debian_dir, "control"), "w") as f:
        f.write(control_content)

    subprocess.run(["fakeroot", "dpkg-deb", "--build", meta_dir], stdout=subprocess.DEVNULL)
    shutil.move(f"{meta_dir}.deb", os.path.join(BASE_DIR, f"{meta_pkg_name}.deb"))
    print("Meta-Paket fertiggestellt!")

if __name__ == "__main__":
    os.makedirs(BASE_DIR, exist_ok=True)
    os.makedirs(os.path.join(BASE_DIR, "build"), exist_ok=True)

    print("Hole Liste der Docsets von der API...")
    r = requests.get(API_URL)
    docsets = r.json()
    
    filtered_docsets = {}

    for ds in docsets:
        title = ds['title']
        name = ds['name']
        source_id = ds.get('sourceId', 'com.kapeli')
        
        #Nur Offizielle Kapeli-Pakete
        if source_id != 'com.kapeli':
            continue
        if "user contributed" in title.lower() or "cheatsheet" in title.lower():
            continue
        if name.endswith("_contrib") or name.endswith("_cheatsheet"):
            continue
            

        # Sucht nach Mustern wie "Bootstrap 5" oder "Java SE25"
        match = re.match(r'^(.*?)\s*([0-9]+(?:\.[0-9]+)*)$', title)
        
        if match:
            base_name = match.group(1).strip()
            version_str = match.group(2)
            # Macht aus "5.1" ein iterierbares Tuple (5, 1) für den korrekten Größenvergleich
            version_tuple = tuple(map(int, version_str.split('.')))
            
            if base_name in filtered_docsets:
                existing_tuple = filtered_docsets[base_name].get('_parsed_version', (0,))
                if version_tuple > existing_tuple:
                    ds['_parsed_version'] = version_tuple
                    filtered_docsets[base_name] = ds
            else:
                ds['_parsed_version'] = version_tuple
                filtered_docsets[base_name] = ds
        else:
            # Hat keine erkennbare Versionsnummer (z.B. "Python", "Angular") -> direkt aufnehmen
            filtered_docsets[title] = ds

    docsets_to_build = list(filtered_docsets.values())
    print(f"\n--> Gefiltert! Baue nur die neuesten {len(docsets_to_build)} Kern-Pakete...\n")

    successful_packages = []

    for ds in docsets_to_build:
        name = ds['name']
        title = ds['title']
        
        download_url = f"https://go.zealdocs.org/d/com.kapeli/{name}/latest"
        
        pkg_name = create_debian_package(name, title, download_url)
        if pkg_name:
            successful_packages.append(pkg_name)
            
        # Direkte RAM/Speicher-Bereinigung nach jedem Paket!
        if os.path.exists(os.path.join(BASE_DIR, "build")):
            shutil.rmtree(os.path.join(BASE_DIR, "build"))

    if successful_packages:
        build_meta_package(successful_packages)
    
    print(f"\nFertig! Alle Pakete liegen in {BASE_DIR}")
