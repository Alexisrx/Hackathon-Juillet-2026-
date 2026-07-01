#!/usr/bin/env bash
#
# status.sh — etat live des VMs via OpenStack CLI + floating IPs.
# Retourne un tableau JSON consommable par le dashboard.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
TFVARS="$INFRA_DIR/vms.auto.tfvars.json"

command -v jq >/dev/null 2>&1 || { echo "jq est requis." >&2; exit 1; }
[[ -f "$INFRA_DIR/openrc-auto.sh" ]] && source "$INFRA_DIR/openrc-auto.sh"

jq -c '.vms | to_entries[] | {
  id: .key,
  owner: .value.owner,
  group: .value.group,
  template: .value.template,
  end_date: .value.end_date
}' "$TFVARS" 2>/dev/null | while read -r vm; do
  ID=$(echo "$vm" | jq -r '.id')
  SERVER="vm-$ID"

  # Statut live depuis OpenStack
  OS_STATUS=$(openstack server show "$SERVER" -f value -c status 2>/dev/null || echo "UNKNOWN")
  case "$OS_STATUS" in
    ACTIVE)          STATUS="up" ;;
    SHUTOFF|STOPPED) STATUS="down" ;;
    BUILD|REBUILD)   STATUS="building" ;;
    *)               STATUS="${OS_STATUS,,}" ;;
  esac

  # Floating IP via OpenStack
  FLOATING_IP=$(openstack server show "$SERVER" -f json 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
addrs = [a for nets in d.get('addresses', {}).values()
         for a in nets if a.get('OS-EXT-IPS:type') == 'floating']
print(addrs[0]['addr'] if addrs else '')
" 2>/dev/null || echo "")

  echo "$vm" | jq --arg status "$STATUS" --arg ip "$FLOATING_IP" \
    '. + {status: $status, floating_ip: $ip}'
done | jq -s '.'
