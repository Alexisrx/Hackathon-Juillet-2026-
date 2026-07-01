# Hackathon Juillet 2026 — Plateforme Cloud Self-Service

**Geneva Institute of Technology × Satom IT & Learning Solutions**  
Infrastructure as Code · Infomaniak Public Cloud · 3 jours

---

## Vue d'ensemble

Plateforme self-service complète pour la gestion du cycle de vie de VMs cloud destinées aux étudiants et formateurs. Un étudiant soumet une demande via le portail web, un validateur l'approuve, la VM est provisionnée automatiquement sur Infomaniak Public Cloud et détruite à son échéance — sans aucune intervention manuelle.

```
Étudiant → Portail web → Validation → Provisioning auto → VM Ubuntu 22.04 → Destruction auto
```

---

## Accès rapide

| Ressource | URL / Commande |
|-----------|---------------|
| Portail web (jury) | http://84.234.27.147 |
| Dépôt Git | https://github.com/Alexisrx/Hackathon-Juillet-2026- |
| Architecture | docs/ADR-001-infrastructure.md |
| Scénario démo | docs/DEMO-SCRIPT.md |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  VM Plateforme (Infomaniak)              │
│  IP: 84.234.27.147                                      │
│                                                          │
│  ┌──────────┐   ┌─────────────┐   ┌──────────────────┐ │
│  │  nginx   │──▶│  Flask app  │──▶│  watch_requests  │ │
│  │  :80     │   │  :5000      │   │  (cron destroy)  │ │
│  └──────────┘   └──────┬──────┘   └────────┬─────────┘ │
│                         │                   │           │
│                    requests/         tofu apply         │
│                   *.json              (OpenStack)       │
└─────────────────────────────────────────────────────────┘
                                │
                    ┌───────────▼────────────┐
                    │   Infomaniak Public    │
                    │   Cloud (OpenStack)    │
                    │                        │
                    │  groupe-a  │  groupe-b │  (isolés)
                    │  VM-001    │  VM-002   │
                    │  VM-003    │  ...      │
                    └────────────────────────┘
```

**Stack technique :** OpenTofu + provider OpenStack, Flask (Python), nginx, cloud-init, bash, jq, systemd.

---

## MUST — Cahier des charges (6/6 ✅)

| Exigence | Implémentation | Preuve |
|----------|---------------|--------|
| Portail de demande avec dates obligatoires | Flask + formulaire HTML | Refus si date de fin absente |
| Workflow de validation | Page `/validate` (approuver/refuser) | `requests/*.json` status |
| Provisioning automatisé | OpenTofu + provider OpenStack | VM ACTIVE sur Infomaniak |
| Destruction automatique à échéance | `destroy_expired.sh` + cron 10min | `logs/destructions.log` |
| Dashboard basique (up/down) | Page `/dashboard` + `status.sh` | Statut ACTIVE/SHUTOFF en live |
| SSH sécurisé + isolation réseau | cloud-init + réseau privé par groupe | `test_isolation.sh` |

## Bonus livrés

- Dashboard de coûts détaillé (par VM + par groupe + total estimé)
- Notification visuelle avant échéance (badge "expire aujourd'hui / expire demain")
- Mini-rapport de fin de hackathon avec journal des destructions

---

## Structure du repo

```
hackathon-platform/
├── infra/
│   ├── main.tf                   # Provider OpenStack, réseaux, VMs, floating IPs
│   ├── variables.tf              # Image Ubuntu 22.04, flavor, réseau externe
│   ├── outputs.tf                # floating_ip par VM
│   ├── vms.auto.tfvars.json      # État désiré (source de vérité)
│   └── openrc-auto.sh.template   # Template credentials OpenStack (ne pas committer openrc-auto.sh)
├── portal/
│   ├── app.py                    # Flask : catalogue, validation, dashboard, rapport
│   ├── templates/                # HTML (base, index, pending, dashboard, report)
│   ├── static/style.css          # Thème console sombre
│   └── run.sh                    # Lancement local avec venv
├── scripts/
│   ├── provision.sh              # Ajoute une VM à l'état désiré + tofu apply
│   ├── destroy_expired.sh        # Nettoie les VMs expirées + tofu apply
│   ├── watch_requests.sh         # Surveille requests/ et provisionne automatiquement
│   ├── status.sh                 # Statut live des VMs (JSON pour le dashboard)
│   ├── test_isolation.sh         # Prouve l'isolation réseau entre deux groupes
│   ├── new_request.sh            # Crée une demande de test sans passer par le portail
│   ├── reset_demo.sh             # Remet l'environnement à zéro avant une démo
│   └── demo.sh                   # Lance watcher + portail en une commande (local)
├── docs/
│   ├── ADR-001-infrastructure.md # Décisions d'architecture justifiées
│   └── DEMO-SCRIPT.md            # Déroulé J3 + Plan B
├── requests/                     # Fichiers JSON des demandes (écrits par le portail)
└── logs/                         # destructions.log + watcher.log
```

---

## Démarrage — VM Plateforme (démo J3)

Le portail et le watcher tournent déjà en production sur la VM plateforme `84.234.27.147`. Pour la démo, rien à démarrer — tout est actif.

Pour vérifier l'état :

```bash
ssh -i /tmp/demo_key ubuntu@84.234.27.147
sudo systemctl status hackathon-portal
tail -f ~/hackathon-platform/logs/watcher.log
```

---

## Démarrage — Machine locale (développement)

### Prérequis

- Docker Desktop + WSL2 (Windows) ou Linux natif
- OpenTofu (`tofu --version`)
- `jq`, `git`, Python 3.10+

### Installation

```bash
git clone https://github.com/Alexisrx/Hackathon-Juillet-2026-.git hackathon-platform
cd hackathon-platform

# Credentials OpenStack (ne jamais committer)
cp infra/openrc-auto.sh.template infra/openrc-auto.sh
nano infra/openrc-auto.sh  # remplir OS_PASSWORD

# Initialiser OpenTofu
source infra/openrc-auto.sh
cd infra && tofu init && cd ..

# Lancer portail + watcher
./scripts/demo.sh
# → http://localhost:5000
```

### Scénario de test complet

```bash
# Générer une clé SSH de test
ssh-keygen -t ed25519 -f /tmp/demo_key -N ""

# Créer et provisionner une VM (sans passer par le portail)
./scripts/new_request.sh req-001 alice groupe-a 2026-07-10 /tmp/demo_key.pub
./scripts/provision.sh requests/req-001.json

# Créer une deuxième VM dans un autre groupe
ssh-keygen -t ed25519 -f /tmp/demo_key2 -N ""
./scripts/new_request.sh req-002 bob groupe-b 2026-07-10 /tmp/demo_key2.pub
./scripts/provision.sh requests/req-002.json

# Prouver l'isolation réseau
./scripts/test_isolation.sh req-001 req-002 /tmp/demo_key

# Tester la destruction automatique
./scripts/new_request.sh req-003 charlie groupe-a 2020-01-01 /tmp/demo_key.pub
./scripts/provision.sh requests/req-003.json
./scripts/destroy_expired.sh   # req-003 disparaît, req-001 et req-002 restent

# Statut JSON (consommé par le dashboard)
./scripts/status.sh
```

---

## Contrat d'interface entre les modules

### Portail → Infra

Le portail écrit un fichier JSON dans `requests/` :

```json
{
  "id": "req-001",
  "owner": "alice",
  "group": "groupe-a",
  "template": "ubuntu-dev",
  "start_date": "2026-07-08",
  "end_date": "2026-07-10",
  "ssh_public_key": "ssh-ed25519 AAAA...",
  "status": "approved"
}
```

`watch_requests.sh` détecte ce fichier et déclenche `provision.sh` automatiquement.

### Infra → Dashboard

`scripts/status.sh` retourne un tableau JSON :

```json
[
  {
    "id": "req-001",
    "owner": "alice",
    "group": "groupe-a",
    "template": "ubuntu-dev",
    "end_date": "2026-07-10",
    "floating_ip": "84.234.25.105",
    "status": "up"
  }
]
```

---

## Sécurité

- **SSH par clé uniquement** : `PasswordAuthentication no`, `PermitRootLogin no` (cloud-init)
- **Utilisateur `student`** sans sudo — clé injectée par cloud-init
- **Isolation réseau** : un réseau OpenStack privé par groupe, des VMs de groupes différents ne peuvent pas se joindre par IP privée
- **Aucune VM sans date de fin** : refus côté portail et côté `provision.sh`
- **Credentials** : `openrc-auto.sh` dans `.gitignore`, jamais commité

---

## Destruction automatique

`scripts/destroy_expired.sh` tourne en cron toutes les 10 minutes sur la VM plateforme :

```
*/10 * * * * /home/ubuntu/hackathon-platform/scripts/destroy_expired.sh
```

Chaque destruction est tracée dans `logs/destructions.log`.

---

## Limites connues (MVP 3 jours)

- **État Terraform local** : `terraform.tfstate` stocké sur la VM plateforme, pas dans un backend distant (S3/Swift). En production, utiliser un backend OpenStack Swift ou Terraform Cloud.
- **Coûts estimés** : indicatifs, basés sur un tarif fixe par template, pas sur les prix réels Infomaniak.
- **Pas de SSO O365** : authentification simple par nom/groupe saisi dans le formulaire.
- **Pas de monitoring Prometheus/Grafana** : le dashboard de statut est basique (ACTIVE/SHUTOFF).

---

*Hackathon Juillet 2026 — Geneva Institute of Technology × Satom IT & Learning Solutions*
