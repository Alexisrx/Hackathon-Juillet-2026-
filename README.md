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

## Portail web (catalogue, validation, dashboard, rapport)

Un portail Flask (`portal/`) couvre les MUST côté Développeur (catalogue de
3 templates, formulaire de demande, workflow de validation) et côté Data
(dashboard up/down, estimation de coûts, mini-rapport), regroupés dans une
seule petite app pour rester simple à lancer en 3 jours. Peut être scindé
en plusieurs services si l'équipe se répartit dessus plus tard — le contrat
avec l'infra (le dossier `requests/`) reste identique dans tous les cas.

```bash
cd portal
./run.sh
# ouvrir http://localhost:5000
```

Pages : `/` (catalogue + demande), `/validate` (file de validation),
`/dashboard` (statut + coûts), `/report` (mini-rapport).

Le portail écrit un fichier JSON dans `requests/` avec `status: "pending"`,
puis `"approved"` ou `"refused"` une fois validé. Il ne connaît rien à
Terraform/Docker : c'est `scripts/watch_requests.sh` (à lancer en parallèle,
voir plus haut) qui détecte les demandes approuvées et déclenche le
provisioning automatiquement.

Pour la démo, lancer dans des terminaux séparés :
```bash
./scripts/watch_requests.sh   # terminal 1 : provisionne automatiquement
cd portal && ./run.sh          # terminal 2 : portail web
```

## Intégration avec l'équipe Développeur

Le contrat d'interface est volontairement minimal : un fichier JSON dans
`requests/` avec `status: "approved"` une fois la demande validée (voir le
format en commentaire dans `scripts/provision.sh`). Le portail fourni dans
`portal/` l'implémente déjà ; si l'équipe Dev préfère reprendre la main,
elle peut remplacer `portal/` par sa propre implémentation tant qu'elle
écrit ce même format dans `requests/`.

## Intégration avec l'équipe Data

`scripts/status.sh` retourne un tableau JSON `[{id, owner, group, template,
end_date, ssh_port, status: "up"|"down"|"unknown"}, ...]`, directement
exploitable pour un dashboard et l'estimation de coûts/usage.
`logs/destructions.log` donne un historique simple pour le mini-rapport de
fin de hackathon. Une implémentation de référence des deux (dashboard +
rapport) est déjà fournie dans `portal/` (`/dashboard`, `/report`) ; à
adapter ou enrichir si l'équipe Data veut une présentation différente.

## Limites connues (MVP 3 jours)

- VMs simulées par des conteneurs Docker, pas une infra cloud réelle
  (changement de provider possible sans réécrire l'architecture, voir ADR).
- Destruction pilotée par un job périodique, pas un mécanisme cloud natif.
- Pas de SSO O365/OIDC réel sur ce module (bonus, hors MUST) — l'identité
  de l'`owner` est transmise telle quelle par le portail.
