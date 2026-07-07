#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "==> Killing any running labzeal / Zeal processes"
pkill -f labzeal 2>/dev/null || true
pkill -f zeal 2>/dev/null || true
sleep 1

echo "==> Purging labzeal package + configuration"
sudo apt-get purge --autoremove labzeal -y 2>/dev/null || true

echo "==> Removing labzeal-demo meta-package"
sudo apt-get purge --autoremove labzeal-demo -y 2>/dev/null || true

echo "==> Removing any remaining docset packages"
DOCSET_PKGS=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep '^labzeal-docset-' | tr '\n' ' ')
if [ -n "$DOCSET_PKGS" ]; then
    sudo apt-get purge --autoremove $DOCSET_PKGS -y 2>/dev/null || true
fi

echo "==> Removing APT source list"
sudo rm -f /etc/apt/sources.list.d/labzeal.list
sudo rm -f /etc/apt/sources.list.d/labzeal.sources

echo "==> Removing local build artifacts"
rm -rf "$SCRIPT_DIR/labzeal_dist"

echo "==> Removing web deployment directory"
sudo rm -rf /var/www/html/labzeal/

echo "==> Clearing APT cache of labzeal entries"
sudo apt-get update 2>/dev/null || true

echo "==> Done! LabZeal has been completely removed."
