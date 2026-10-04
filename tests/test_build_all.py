"""Automatisierte Pruefungen fuer build_all.py.

Stufe 1: reine Funktionen, offline.
Stufe 2: gebaute Artefakte; wird uebersprungen, wenn kein Docset-Paket vorliegt.
         Pfad ueber die Umgebungsvariable LABZEAL_TEST_DEB setzbar.
Stufe 3: Marker 'network', benoetigt die Kapeli-API (pytest -m network).
"""
import glob
import os
import sqlite3
import subprocess
import sys

import pytest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_ROOT)

import build_all  # noqa: E402


def _ds(name, title, source="com.kapeli"):
    return {"name": name, "title": title, "sourceId": source}


# ------------------------------------------------------------- Stufe 1
@pytest.mark.parametrize("raw,expected", [
    ("Python 3", "labzeal-docset-python3"),
    ("python_3", "labzeal-docset-python-3"),
    ("C++", "labzeal-docset-c++"),
    ("NodeJS", "labzeal-docset-nodejs"),
    ("Bootstrap 5", "labzeal-docset-bootstrap5"),
    ("Angular/JS!", "labzeal-docset-angularjs"),
    ("Vue.js", "labzeal-docset-vue.js"),
])
def test_sanitize_package_name(raw, expected):
    assert build_all.sanitize_package_name(raw) == expected


def test_sanitize_package_name_strips_non_ascii():
    assert build_all.sanitize_package_name("Ärger") == "labzeal-docset-rger"


def test_filter_latest_versions_keeps_highest():
    out = build_all.filter_latest_versions([
        _ds("bootstrap_5", "Bootstrap 5"),
        _ds("bootstrap_4", "Bootstrap 4"),
        _ds("bootstrap_3_3_7", "Bootstrap 3.3.7"),
    ])
    assert [d["title"] for d in out] == ["Bootstrap 5"]


def test_filter_latest_versions_keeps_unversioned_titles():
    out = build_all.filter_latest_versions([_ds("python_3", "Python 3"), _ds("django", "Django")])
    assert {d["title"] for d in out} == {"Python 3", "Django"}


def test_filter_latest_versions_drops_non_kapeli_and_helpers():
    out = build_all.filter_latest_versions([
        _ds("x", "X", source="user"),
        _ds("y", "Y (cheatsheet)"),
        _ds("z_contrib", "Z"),
        _ds("w_cheatsheet", "W"),
    ])
    assert out == []


def test_build_control_content_fields():
    ctrl = build_all.build_control_content("labzeal-docset-c++", "C++")
    assert "Package: labzeal-docset-c++" in ctrl
    assert "Depends: labzeal" in ctrl
    assert "Architecture: all" in ctrl
    assert "Description: LabZeal with the C++ Docset" in ctrl


def test_meta_package_name():
    assert build_all.META_PACKAGE_NAME == "labzeal-all"


# ------------------------------------------------------------- Stufe 2
def _find_docset_deb():
    env = os.environ.get("LABZEAL_TEST_DEB")
    if env and os.path.exists(env):
        return env
    for pattern in ("labzeal_dist/*.deb", "/var/www/html/labzeal/debs/*.deb"):
        hits = sorted(glob.glob(pattern if pattern.startswith("/") else os.path.join(REPO_ROOT, pattern)))
        for hit in hits:
            if "docset" in os.path.basename(hit):
                return hit
    return None


DOCSET_DEB = _find_docset_deb()


@pytest.mark.skipif(not DOCSET_DEB, reason="kein Docset-Paket gefunden")
def test_docset_depends_on_core():
    ctrl = subprocess.run(["dpkg-deb", "-f", DOCSET_DEB, "Package", "Depends"],
                          capture_output=True, text=True, check=True).stdout
    assert "Depends: labzeal" in ctrl


@pytest.mark.skipif(not DOCSET_DEB, reason="kein Docset-Paket gefunden")
def test_docset_archive_permissions():
    listing = subprocess.run(["dpkg-deb", "-c", DOCSET_DEB],
                             capture_output=True, text=True, check=True).stdout
    assert "root/root" in listing
    assert any(line.startswith("-rw-r--r--") for line in listing.splitlines())
    assert any(line.startswith("drwxrwxr-x") for line in listing.splitlines())


@pytest.mark.skipif(not DOCSET_DEB, reason="kein Docset-Paket gefunden")
def test_search_index_present_and_populated(tmp_path):
    subprocess.run(["dpkg-deb", "-x", DOCSET_DEB, str(tmp_path)], check=True)
    dbs = glob.glob(str(tmp_path) + "/**/docSet.dsidx", recursive=True)
    assert dbs, "keine docSet.dsidx im Paket"
    for db in dbs:
        with sqlite3.connect(db) as con:
            tables = [r[0] for r in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table'")]
            assert "searchIndex" in tables
            assert con.execute("SELECT count(*) FROM searchIndex").fetchone()[0] > 0
            assert con.execute("PRAGMA journal_mode").fetchone()[0].lower() == "delete"


# ------------------------------------------------------------- Stufe 3
@pytest.mark.network
def test_build_limit_one_end_to_end(tmp_path):
    env = dict(os.environ)
    env["PYTHONPATH"] = REPO_ROOT
    subprocess.run([sys.executable, os.path.join(REPO_ROOT, "build_all.py"),
                    "--limit", "1", "--output", str(tmp_path)],
                   env=env, check=True, timeout=900)
    names = [os.path.basename(p) for p in glob.glob(str(tmp_path) + "/*.deb")]
    assert any(n.startswith("labzeal-docset-") for n in names), names
