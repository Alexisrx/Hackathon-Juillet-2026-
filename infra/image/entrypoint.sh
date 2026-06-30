#!/bin/bash
# Injecte la cle publique SSH fournie par la plateforme (via variable d'env)
# puis demarre sshd au premier plan. Aucun mot de passe n'est jamais defini :
# seule l'authentification par cle est possible.
set -euo pipefail

if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "ERREUR: SSH_PUBLIC_KEY n'est pas definie, impossible de demarrer la VM." >&2
  exit 1
fi

mkdir -p /home/student/.ssh
echo "$SSH_PUBLIC_KEY" > /home/student/.ssh/authorized_keys
chmod 700 /home/student/.ssh
chmod 600 /home/student/.ssh/authorized_keys
chown -R student:student /home/student/.ssh

# verrouille le compte root et bloque tout mot de passe pour student
passwd -l root >/dev/null 2>&1 || true
passwd -l student >/dev/null 2>&1 || true

exec /usr/sbin/sshd -D
