#!/usr/bin/env bash
#
# new_request.sh — cree une demande approuvee pour tester le pipeline.
# Usage : ./new_request.sh <id> <owner> <group> <end_date:YYYY-MM-DD> <cle_pub>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_DIR="$SCRIPT_DIR/../requests"
mkdir -p "$REQ_DIR"

ID="${1:?id requis}"
OWNER="${2:?owner requis}"
GROUP="${3:?group requis}"
END_DATE="${4:?end_date requis (YYYY-MM-DD)}"
KEY_PATH="${5:?chemin vers la cle publique SSH requis}"

[[ -f "$KEY_PATH" ]] || { echo "Cle publique introuvable: $KEY_PATH" >&2; exit 1; }
SSH_KEY=$(cat "$KEY_PATH")

cat > "$REQ_DIR/$ID.json" << ENDJSON
{
  "id": "$ID",
  "owner": "$OWNER",
  "group": "$GROUP",
  "template": "ubuntu-dev",
  "start_date": "$(date +%Y-%m-%d)",
  "end_date": "$END_DATE",
  "ssh_public_key": "$SSH_KEY",
  "status": "approved"
}
ENDJSON

echo "Demande creee : $REQ_DIR/$ID.json"
echo "Provisionner avec : ./provision.sh $REQ_DIR/$ID.json"
