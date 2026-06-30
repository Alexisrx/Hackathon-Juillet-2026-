#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"

read -p "Ceci va detruire TOUTES les VMs actives et effacer requests/ + le journal. Continuer ? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Annule."
  exit 0
fi

echo '{
  "vms": {}
}' > "$INFRA_DIR/vms.auto.tfvars.json"

( cd "$INFRA_DIR" && tofu apply -auto-approve )

rm -f "$SCRIPT_DIR/../requests"/*.json
: > "$SCRIPT_DIR/../logs/destructions.log"

echo "==> Environnement reinitialise. Pret pour une nouvelle demo."
