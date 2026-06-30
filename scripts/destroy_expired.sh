#!/usr/bin/env bash
#
# destroy_expired.sh — applique l'exigence "aucune VM sans date de fin".
# A executer periodiquement (cron toutes les 5-15 min, ou systemd timer).
#
# Principe : retire de l'etat desire (vms.auto.tfvars.json) toute VM dont
# end_date < aujourd'hui, puis relance `tofu apply`. Comme l'etat desire
# ne contient plus ces VMs, Tofu les detruit automatiquement (pas besoin
# de cibler chaque ressource manuellement).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
TFVARS="$INFRA_DIR/vms.auto.tfvars.json"
LOG_FILE="$SCRIPT_DIR/../logs/destructions.log"
TODAY=$(date +%Y-%m-%d)

mkdir -p "$(dirname "$LOG_FILE")"
command -v jq >/dev/null 2>&1 || { echo "jq est requis." >&2; exit 1; }

EXPIRED=$(jq -r --arg today "$TODAY" \
  '.vms | to_entries[] | select(.value.end_date < $today) | .key' "$TFVARS")

if [[ -z "$EXPIRED" ]]; then
  echo "$(date -Iseconds) - aucune VM expiree" >> "$LOG_FILE"
  exit 0
fi

for ID in $EXPIRED; do
  GROUP=$(jq -r --arg id "$ID" '.vms[$id].group' "$TFVARS")
  END_DATE=$(jq -r --arg id "$ID" '.vms[$id].end_date' "$TFVARS")
  echo "$(date -Iseconds) - destruction VM expiree id=$ID group=$GROUP end_date=$END_DATE" | tee -a "$LOG_FILE"
  jq --arg id "$ID" 'del(.vms[$id])' "$TFVARS" > "$TFVARS.tmp"
  mv "$TFVARS.tmp" "$TFVARS"
done

( cd "$INFRA_DIR" && tofu apply -auto-approve )

echo "$(date -Iseconds) - reconciliation terminee, $(echo "$EXPIRED" | wc -l) VM(s) detruite(s)" >> "$LOG_FILE"
