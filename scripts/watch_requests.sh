#!/usr/bin/env bash
#
# watch_requests.sh — surveille requests/*.json et provisionne automatiquement
# toute nouvelle demande approuvee. A lancer dans un terminal dedie (ou en
# arriere-plan) pendant le hackathon : le portail web (equipe Developpeur)
# n'a alors qu'a ecrire un fichier JSON avec status="approved", sans avoir
# a invoquer provision.sh ni a connaitre Terraform/OpenTofu.
#
# Usage : ./watch_requests.sh [intervalle_secondes]   (defaut: 5)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_DIR="$SCRIPT_DIR/../requests"
TFVARS="$SCRIPT_DIR/../infra/vms.auto.tfvars.json"
INTERVAL="${1:-5}"

command -v jq >/dev/null 2>&1 || { echo "jq est requis." >&2; exit 1; }

echo "Surveillance de $REQ_DIR toutes les ${INTERVAL}s (Ctrl+C pour arreter)..."

while true; do
  for REQ_FILE in "$REQ_DIR"/*.json; do
    [[ -e "$REQ_FILE" ]] || continue

    ID=$(jq -r '.id // empty' "$REQ_FILE")
    [[ -n "$ID" ]] || continue

    STATUS=$(jq -r '.status // empty' "$REQ_FILE")
    ALREADY=$(jq -r --arg id "$ID" '.vms | has($id)' "$TFVARS")

    if [[ "$STATUS" == "approved" && "$ALREADY" == "false" ]]; then
      echo "==> Nouvelle demande approuvee detectee : $ID"
      if "$SCRIPT_DIR/provision.sh" "$REQ_FILE"; then
        echo "==> $ID provisionnee automatiquement."
      else
        echo "ERREUR lors du provisioning de $ID (voir sortie ci-dessus)" >&2
      fi
    fi
  done
  sleep "$INTERVAL"
done
