#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"

ID_A="${1:?Usage: test_isolation.sh <id_a> <id_b> <cle_privee>}"
ID_B="${2:?Usage: test_isolation.sh <id_a> <id_b> <cle_privee>}"
KEY="${3:-/tmp/demo_key}"

[[ -f "$INFRA_DIR/openrc-auto.sh" ]] && source "$INFRA_DIR/openrc-auto.sh"

# Floating IP de VM_A depuis tofu output (deja calcule)
FLOATING_A=$(cd "$INFRA_DIR" && tofu output -json vms 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$ID_A', {}).get('floating_ip', ''))")

# IP privee de VM_B via le port OpenStack (nom connu : hackathon-port-<id>)
PRIVATE_B=$(openstack port show "hackathon-port-$ID_B" -f value -c fixed_ips 2>/dev/null | \
  grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)

if [[ -z "$FLOATING_A" || -z "$PRIVATE_B" ]]; then
  echo "Impossible de recuperer les IPs (VMs provisionnees ?)." >&2
  echo "FLOATING_A=$FLOATING_A PRIVATE_B=$PRIVATE_B" >&2
  exit 1
fi

echo "Test isolation : vm-$ID_A ($FLOATING_A) tente de joindre vm-$ID_B IP privee ($PRIVATE_B)..."
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
if ssh $SSH_OPTS student@"$FLOATING_A" ping -c 2 -W 3 "$PRIVATE_B" 2>/dev/null; then
  echo "ECHEC : isolation rompue !"
  exit 1
else
  echo "OK : vm-$ID_A ne peut pas joindre vm-$ID_B via IP privee -> isolation confirmee."
  exit 0
fi
