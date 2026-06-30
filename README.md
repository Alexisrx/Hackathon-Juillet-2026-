# Hackathon Juillet 2026 — Module Système & Réseau

Provisioning automatisé de VMs (simulées via Docker), destruction
automatique à échéance, accès SSH sécurisé et isolation réseau entre
groupes. Voir [`docs/ADR-001-infrastructure.md`](docs/ADR-001-infrastructure.md)
pour le détail des choix.

## Prérequis

- Docker
- [OpenTofu](https://opentofu.org/docs/intro/install/) (`tofu`)
- `jq`

## Démarrage rapide

```bash
# 1. construire l'image de base utilisée pour chaque VM
docker build -t hackathon-vm-base:latest infra/image

# 2. initialiser Terraform/OpenTofu
cd infra && tofu init && cd ..

# 3. générer une paire de clés de test (si besoin)
ssh-keygen -t ed25519 -f /tmp/demo_key -N ""

# 4. simuler une demande approuvée par le portail (équipe Dev)
./scripts/new_request.sh req-001 alice groupe-a 2026-07-10 /tmp/demo_key.pub

# 5. provisionner la VM correspondante
./scripts/provision.sh requests/req-001.json

# 6. se connecter en SSH
ssh -i /tmp/demo_key -p 2200 student@localhost

# 7. voir le statut de toutes les VMs (format consommé par le dashboard Data)
./scripts/status.sh
```

## Scénario de démo de bout en bout

1. `new_request.sh` pour créer une demande (simule le portail).
2. `provision.sh` : la VM apparaît (`docker ps`), SSH fonctionne.
3. Créer une deuxième VM dans un **autre** groupe, puis lancer
   `./scripts/test_isolation.sh req-001 req-002` pour prouver en direct
   que les deux groupes ne peuvent pas se joindre.
4. Créer une troisième demande avec une `end_date` déjà passée, lancer
   `./scripts/destroy_expired.sh` et montrer que la VM est détruite
   automatiquement (`docker ps` ne la montre plus, `logs/destructions.log`
   trace l'événement).
5. `./scripts/status.sh` pour montrer le flux JSON consommé par le
   dashboard de l'équipe Data.

## Automatisation de la destruction

`scripts/destroy_expired.sh` est conçu pour tourner en tâche périodique.
En hackathon, le plus simple :

```bash
# toutes les 10 minutes
crontab -e
*/10 * * * * /chemin/vers/hackathon-platform/scripts/destroy_expired.sh
```

Une alternative systemd (`unit` + `timer`) est fournie en exemple dans
`scripts/hackathon-destroy.timer.example`.

## Intégration avec l'équipe Développeur

Le contrat d'interface est volontairement minimal : le portail web écrit un
fichier JSON dans `requests/` avec `status: "approved"` une fois la demande
validée (voir le format en commentaire dans `scripts/provision.sh`). Le
portail peut soit appeler `provision.sh` directement (exec ou webhook),
soit laisser un job qui surveille `requests/*.json` et les traite au fil de
l'eau. Aucune dépendance inverse : ce module n'a pas besoin de connaître
l'implémentation du portail.

## Intégration avec l'équipe Data

`scripts/status.sh` retourne un tableau JSON `[{id, owner, group, template,
end_date, ssh_port, status: "up"|"down"|"unknown"}, ...]`, directement
exploitable pour le dashboard et l'estimation de coûts/usage.
`logs/destructions.log` donne un historique simple pour le mini-rapport de
fin de hackathon.

## Limites connues (MVP 3 jours)

- VMs simulées par des conteneurs Docker, pas une infra cloud réelle
  (changement de provider possible sans réécrire l'architecture, voir ADR).
- Destruction pilotée par un job périodique, pas un mécanisme cloud natif.
- Pas de SSO O365/OIDC réel sur ce module (bonus, hors MUST) — l'identité
  de l'`owner` est transmise telle quelle par le portail.
