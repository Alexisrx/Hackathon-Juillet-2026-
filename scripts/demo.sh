#!/usr/bin/env bash
# demo.sh — lance le watcher + le portail en une seule commande.
# Source openrc-auto.sh pour que le watcher ait les credentials OpenStack.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$SCRIPT_DIR/../infra/openrc-auto.sh" ]] || {
  echo "ERREUR : infra/openrc-auto.sh manquant (copier le template et remplir le mot de passe)." >&2
  exit 1
}
source "$SCRIPT_DIR/../infra/openrc-auto.sh"
mkdir -p "$SCRIPT_DIR/../logs"

echo "==> Demarrage du watcher en arriere-plan (logs: logs/watcher.log)"
nohup "$SCRIPT_DIR/watch_requests.sh" > "$SCRIPT_DIR/../logs/watcher.log" 2>&1 &
WATCHER_PID=$!
echo "    watcher PID=$WATCHER_PID"

cleanup() {
  echo
  echo "==> Arret du watcher (PID=$WATCHER_PID)..."
  kill "$WATCHER_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Demarrage du portail (http://localhost:5000)"
cd "$SCRIPT_DIR/../portal"
./run.sh
