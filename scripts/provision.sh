#!/usr/bin/env bash
#
# provision.sh — declenche le provisioning d'une VM a partir d'une demande
# approuvee par le workflow de validation (cote Developpeur).
#
# Usage : ./provision.sh <chemin/vers/requete.json>
#
# Format attendu du fichier de requete (ecrit par le portail) :
# {
#   "id": "req-001",
#   "owner": "alice",
#   "group": "groupe-a",
#   "template": "ubuntu-base",
#   "start_date": "2026-07-08",
#   "end_date": "2026-07-10",
#   "ssh_public_key": "ssh-ed25519 AAAA...",
#   "status": "approved"
# }
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
TFVARS="$INFRA_DIR/vms.auto.tfvars.json"
REQ_FILE="${1:?Usage: provision.sh <requete.json>}"

command -v jq >/dev/null 2>&1 || { echo "jq est requis." >&2; exit 1; }
[[ -f "$REQ_FILE" ]] || { echo "Fichier de requete introuvable: $REQ_FILE" >&2; exit 1; }

STATUS=$(jq -r '.status' "$REQ_FILE")
if [[ "$STATUS" != "approved" ]]; then
  echo "Demande $REQ_FILE non approuvee (status=$STATUS) -> aucun provisioning."
  exit 0
fi

ID=$(jq -r '.id' "$REQ_FILE")
OWNER=$(jq -r '.owner' "$REQ_FILE")
GROUP=$(jq -r '.group' "$REQ_FILE")
TEMPLATE=$(jq -r '.template' "$REQ_FILE")
END_DATE=$(jq -r '.end_date' "$REQ_FILE")
SSH_KEY=$(jq -r '.ssh_public_key' "$REQ_FILE")

if [[ -z "$END_DATE" || "$END_DATE" == "null" ]]; then
  echo "Refus : aucune VM ne peut etre creee sans date de fin (id=$ID)." >&2
  exit 1
fi

# Choix d'un port SSH externe libre (incrementale, simple pour le hackathon)
COUNT=$(jq '.vms | length' "$TFVARS")
SSH_PORT=$((2200 + COUNT))

jq --arg id "$ID" --arg owner "$OWNER" --arg group "$GROUP" \
   --arg template "$TEMPLATE" --arg end_date "$END_DATE" \
   --arg ssh_key "$SSH_KEY" --argjson ssh_port "$SSH_PORT" \
   '.vms[$id] = {owner: $owner, group: $group, template: $template, end_date: $end_date, ssh_public_key: $ssh_key, ssh_port: $ssh_port}' \
   "$TFVARS" > "$TFVARS.tmp"
mv "$TFVARS.tmp" "$TFVARS"

echo "==> VM $ID ajoutee a l'etat desire (groupe=$GROUP, fin=$END_DATE)."
echo "==> Application Terraform/OpenTofu..."

( cd "$INFRA_DIR" && tofu apply -auto-approve )

# met a jour le statut de la requete pour que le portail (et le dashboard) le voient
jq '.status = "provisioned"' "$REQ_FILE" > "$REQ_FILE.tmp" && mv "$REQ_FILE.tmp" "$REQ_FILE"

echo "==> VM $ID provisionnee. Connexion : ssh student@<host> -p $SSH_PORT"
