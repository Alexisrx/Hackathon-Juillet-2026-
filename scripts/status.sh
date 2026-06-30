#!/usr/bin/env bash
#
# status.sh — expose l'etat de toutes les VMs (up/down) en JSON, a destination
# du dashboard de l'equipe Data. A appeler directement, ou a brancher derriere
# un petit serveur HTTP (ex: `watch -n5` + fichier statique, ou un endpoint
# Flask minimal qui execute ce script et renvoie sa sortie).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
TFVARS="$INFRA_DIR/vms.auto.tfvars.json"

command -v jq >/dev/null 2>&1 || { echo "jq est requis." >&2; exit 1; }

jq -c '.vms | to_entries[] | {
  id: .key,
  owner: .value.owner,
  group: .value.group,
  template: .value.template,
  end_date: .value.end_date,
  ssh_port: .value.ssh_port
}' "$TFVARS" | while read -r vm; do
  ID=$(echo "$vm" | jq -r '.id')
  CONTAINER="vm-$ID"
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER")
    if [[ "$RUNNING" == "true" ]]; then STATE="up"; else STATE="down"; fi
  else
    STATE="unknown"
  fi
  echo "$vm" | jq --arg state "$STATE" '. + {status: $state}'
done | jq -s '.'
