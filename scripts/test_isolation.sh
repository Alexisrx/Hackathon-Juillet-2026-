#!/usr/bin/env bash
#
# test_isolation.sh — prouve que deux VMs de groupes differents ne peuvent
# pas se joindre via leurs IPs privees (isolation reseau OpenStack).
#
# Usage : ./test_isolation.sh <id_vm_a> <id_vm_b> <chemin_cle_privee>
# Exemple : ./test_isolation.sh req-001 req-002 /tmp/demo_key
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"

ID_A="${1:?Usage: test_isolation.sh <id_a> <id_b> <cle_privee>}"
ID_B="${2:?Usage: test_isolation.sh <id_a> <id_b> <cle_privee>}"
KEY="${3:-/tmp/demo_key}"

[[ -f "$INFRA_DIR/openrc-auto.sh" ]] && source "$INFRA_DIR/openrc-auto.sh"

# Floating IP de VM_A (pour s'y connecter en SSH)
FLOATING_A=$(openstack server show "vm-$ID_A" -f json 2>/dev/null | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
addrs = [a for nets in d.get('addresses', {}).values()
         for a in nets if a.get('OS-EXT-IPS:type') == 'floating']
print(addrs[0]['addr'] if addrs else '')
")

# IP privee de VM_B (la cible — pas accessible directement de l'exterieur)
PRIVATE_B=$(openstack server show "vm-$ID_B" -f json 2>/dev/null | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
addrs = [a for nets in d.get('addresses', {}).values()
         for a in nets if a.get('OS-EXT-IPS:type') == 'fixed']
print(addrs[0]['addr'] if addrs else '')
")

if [[ -z "$FLOATING_A" || -z "$PRIVATE_B" ]]; then
  echo "Impossible de recuperer les IPs des VMs (sont-elles provisionnees ?)." >&2
  exit 1
fi

echo "Test isolation : vm-$ID_A ($FLOATING_A) tente de joindre vm-$ID_B IP privee ($PRIVATE_B)..."
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
if ssh $SSH_OPTS student@"$FLOATING_A" ping -c 2 -W 3 "$PRIVATE_B" 2>/dev/null; then
  echo "ECHEC : vm-$ID_A peut joindre vm-$ID_B -> isolation rompue !"
  exit 1
else
  echo "OK : vm-$ID_A ne peut pas joindre vm-$ID_B via IP privee -> isolation confirmee."
  exit 0
fi
