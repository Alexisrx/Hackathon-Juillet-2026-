#!/usr/bin/env bash
#
# reset_demo.sh — remet l'environnement a zero pour repartir sur une demo
# propre : detruit toutes les VMs actives, vide requests/ et le journal de
# destruction. A utiliser avant la repetition finale ou la vraie demo J3.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
[[ -f "$INFRA_DIR/openrc-auto.sh" ]] && source "$INFRA_DIR/openrc-auto.sh"

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
