#!/usr/bin/env bash
#
# test_isolation.sh — verifie qu'une VM d'un groupe ne peut PAS joindre
# une VM d'un autre groupe. A utiliser pendant la demo pour prouver
# l'isolation reseau en direct.
#
# Usage : ./test_isolation.sh <id_vm_a> <id_vm_b>
# (id_vm_a et id_vm_b doivent appartenir a deux groupes differents)
#
set -euo pipefail

VM_A="vm-${1:?Usage: test_isolation.sh <id_vm_a> <id_vm_b>}"
VM_B="vm-${2:?Usage: test_isolation.sh <id_vm_a> <id_vm_b>}"

IP_B=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$VM_B" | awk '{print $1}')

if [[ -z "$IP_B" ]]; then
  echo "Impossible de recuperer l'IP de $VM_B." >&2
  exit 1
fi

echo "Test : $VM_A tente de joindre $VM_B ($IP_B)..."
if docker exec "$VM_A" ping -c 2 -W 2 "$IP_B" >/dev/null 2>&1; then
  echo "ECHEC : $VM_A peut joindre $VM_B -> l'isolation reseau est rompue."
  exit 1
else
  echo "OK : $VM_A ne peut pas joindre $VM_B -> isolation confirmee."
  exit 0
fi
