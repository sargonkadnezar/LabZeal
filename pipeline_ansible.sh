#!/bin/bash
# pipeline_ansible.sh
# Variante von pipeline.sh mit signiertem Repository und Ansible-Deployment (Proof of Concept).
# Unterschiede zur Basisvariante:
#   - Phase 2 nutzt deploy_local_gpg.sh (Release-Signierung statt "Trusted: yes")
#   - Phase 3 installiert/aktualisiert labzeal-all ueber das Playbook ansible/deploy_labzeal.yml
# Voraussetzung: ansible-core (ansible-playbook) ist installiert.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LIMIT=12
WORKERS=0
DO_DEPLOY=false
DO_INSTALL=false
DO_CLEANUP=false
SKIP_EXISTING="--skip-existing"

usage() {
    echo "Usage: $0 [options]"
    echo "  --limit N       Number of docsets to build (default: 12)"
    echo "  --workers N     Thread pool size (default: auto)"
    echo "  --full          Rebuild all, skip none"
    echo "  --deploy        Run deploy_local_gpg.sh after build"
    echo "  --install       Deploy AND install/upgrade labzeal-all via Ansible"
    echo "  --cleanup       Run cleanup.sh first (nuke everything)"
    echo "  -h, --help      Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --limit)     LIMIT="$2"; shift 2 ;;
        --workers)   WORKERS="$2"; shift 2 ;;
        --full)      SKIP_EXISTING=""; shift ;;
        --deploy)    DO_DEPLOY=true; shift ;;
        --install)   DO_INSTALL=true; DO_DEPLOY=true; shift ;;
        --cleanup)   DO_CLEANUP=true; shift ;;
        -h|--help)   usage ;;
        *)           echo "Unknown option: $1"; usage ;;
    esac
done

if $DO_CLEANUP; then
    echo "==> Phase 0: Cleanup"
    bash cleanup.sh
    echo ""
fi

echo "==> Phase 1: Build docset packages"

# Auto-cap workers at limit so we never spawn more threads than docsets
if [ "$WORKERS" -eq 0 ]; then
    CPU_COUNT=$(nproc 2>/dev/null || echo 4)
    WORKERS=$(( CPU_COUNT < LIMIT ? CPU_COUNT : LIMIT ))
    [ "$WORKERS" -lt 1 ] && WORKERS=1
fi

PYTHON_ARGS="--limit $LIMIT --workers $WORKERS $SKIP_EXISTING"

python3 build_all.py $PYTHON_ARGS

if $DO_DEPLOY; then
    echo ""
    echo "==> Phase 2: Deploy (signiert)"
    bash deploy_local_gpg.sh
fi

if $DO_INSTALL; then
    echo ""
    echo "==> Phase 3: Install / Upgrade via Ansible"
    ansible-playbook ansible/deploy_labzeal.yml
fi

echo ""
echo "==> Pipeline complete."