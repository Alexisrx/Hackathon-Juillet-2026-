# Hackathon Juillet 2026 — Plateforme Cloud Self-Service

**Geneva Institute of Technology × Satom IT & Learning Solutions**  
Infrastructure as Code · Infomaniak Public Cloud · 3 jours

---

## Vue d'ensemble

Plateforme self-service complète pour la gestion du cycle de vie de VMs cloud destinées aux étudiants et formateurs. Un étudiant soumet une demande via le portail web, un validateur l'approuve, la VM est provisionnée automatiquement sur Infomaniak Public Cloud avec un réseau isolé par groupe, et détruite à son échéance — sans aucune intervention manuelle.

```
Étudiant → Portail web → Validation → Provisioning auto → VM Ubuntu 22.04 → Destruction auto
```

---

## Accès rapide

| Ressource | Valeur |
|-----------|--------|
| Portail web (jury) | http://84.234.27.147 |
| Dépôt Git | https://github.com/Alexisrx/Hackathon-Juillet-2026- |
| Architecture | docs/ADR-001-infrastructure.md |
| Scénario démo | docs/DEMO-SCRIPT.md |
| Rapport technique | docs/RAPPORT-TECHNIQUE.md |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET                              │
│                                                              │
│  Jury / Étudiants              Administrateur               │
│  http://84.234.27.147          ssh ubuntu@84.234.27.147     │
└───────────────┬────────────────────────────┬────────────────┘
                │ :80                        │ :22
                ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│           VM Plateforme (Infomaniak Public Cloud)            │
│           IP publique : 84.234.27.147                        │
│           Réseau : hackathon-groupe-a (hors IaC)            │
│                                                              │
│  ┌─────────┐   ┌──────────────┐   ┌─────────────────────┐  │
│  │  nginx  │──▶│  Flask :5000 │   │  watch_requests.sh  │  │
│  │  :80    │   │  (portail)   │   │  (watcher continu)  │  │
│  └─────────┘   └──────┬───────┘   └──────────┬──────────┘  │
│                        │ écrit                │ lit         │
│                        ▼                      ▼             │
│                  requests/*.json ◀────────────┘             │
│                        │ provision.sh + tofu apply          │
│  cron */10min          ▼                                    │
│  destroy_expired.sh ───┘                                    │
└─────────────────────────────────────────────────────────────┘
                         │ OpenStack API
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Infomaniak Public Cloud (OpenStack)             │
│              Région : dc3-a  Projet : PCP-YV8RZH7           │
│                                                              │
│  ┌──────────────────────┐   ┌──────────────────────┐        │
│  │  Réseau groupe-b     │   │  Réseau groupe-c     │  ...  │
│  │  192.168.10.0/24     │   │  192.168.20.0/24     │        │
│  │                      │   │                      │        │
│  │  vm-req-001          │   │  vm-req-002          │        │
│  │  Ubuntu 22.04        │   │  Ubuntu 22.04        │        │
│  │  195.15.196.105      │   │  (floating IP)       │        │
│  └──────────────────────┘   └──────────────────────┘        │
│    (isolés — CIDRs uniques, pas de route entre groupes)     │
└─────────────────────────────────────────────────────────────┘
```

**Stack technique :** OpenTofu 1.12.3 + provider OpenStack 3.4.0, Flask (Python 3.10), nginx, cloud-init, bash, jq, systemd, cron.

---

## MUST — Cahier des charges (6/6 ✅)

| # | Exigence | Implémentation | Preuve |
|---|----------|---------------|--------|
| 1 | Portail de demande avec dates obligatoires | Flask + validation serveur | Refus si `end_date` absente |
| 2 | Workflow de validation (approbation/refus) | Page `/validate` | `requests/*.json` status |
| 3 | Provisioning automatisé d'au moins 1 VM | OpenTofu + OpenStack | VM ACTIVE sur Infomaniak |
| 4 | Destruction automatique à échéance | `destroy_expired.sh` + cron 10min | `logs/destructions.log` |
| 5 | Dashboard basique (up/down) | Page `/dashboard` + `status.sh` | Statut ACTIVE/SHUTOFF live |
| 6 | SSH sécurisé + isolation réseau | cloud-init + réseaux privés séparés | `test_isolation.sh` |

## Bonus livrés

| Bonus | Implémentation |
|-------|---------------|
| Dashboard de coûts détaillé | Coût par VM + par groupe + total estimé en CHF |
| Notification avant échéance | Badge "expire aujourd'hui / expire demain" sur le dashboard |

---

## Isolation réseau — CIDRs uniques par groupe

Chaque groupe d'étudiants reçoit un réseau OpenStack privé avec un CIDR unique, dérivé automatiquement de la position alphabétique du groupe :

| Groupe (ordre alpha) | CIDR | Exemple |
|---------------------|------|---------|
| 1er groupe (groupe-b) | 192.168.10.0/24 | ✅ actif |
| 2ème groupe (groupe-c) | 192.168.20.0/24 | — |
| 3ème groupe (groupe-d) | 192.168.30.0/24 | — |
| ... | ... | Jusqu'à 25 groupes |

**Pourquoi des CIDRs uniques ?** Un futur bastion connecté à tous les réseaux doit pouvoir router sans ambiguïté. Avec tous les groupes sur `10.10.0.0/24`, le système d'exploitation ne saurait pas par quelle interface joindre `192.168.10.128` — avec des CIDRs distincts, le routage est déterministe.

**Calcul en Terraform :**
```hcl
locals {
  groups_list = sort(tolist(toset([for k, v in var.vms : v.group])))
  group_cidrs = {
    for idx, g in local.groups_list :
    g => "192.168.${(idx + 1) * 10}.0/24"
  }
}
```

---

## Structure du repo

```
hackathon-platform/
├── infra/
│   ├── main.tf                   # Réseaux, VMs, floating IPs (CIDRs uniques)
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
│   ├── DEMO-SCRIPT.md            # Déroulé J3 + Plan B
│   └── RAPPORT-TECHNIQUE.md      # Rapport complet du projet
├── requests/                     # Fichiers JSON des demandes (écrits par le portail)
└── logs/                         # destructions.log + watcher.log
```

---

## Démarrage — VM Plateforme (démo J3)

Le portail et le watcher tournent déjà en production. Pour vérifier l'état :

```bash
ssh -i /tmp/demo_key ubuntu@84.234.27.147
sudo systemctl status hackathon-portal     # Flask : active (running)
ps aux | grep watch_requests               # watcher actif
crontab -l                                 # cron destroy configuré
```

---

## Démarrage — Machine locale (développement)

### Prérequis

- Docker Desktop + WSL2 (Windows) ou Linux natif
- OpenTofu (`tofu --version`)
- `jq`, `git`, Python 3.10+
- Client OpenStack (`python3-openstackclient`)

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

# Lancer portail + watcher en local
./scripts/demo.sh
# → http://localhost:5000
```

### Scénario de test complet

```bash
# Générer une clé SSH de test
ssh-keygen -t ed25519 -f /tmp/demo_key -N ""

# Créer et provisionner une VM dans groupe-b (CIDR : 192.168.10.0/24)
./scripts/new_request.sh req-001 alice groupe-b 2026-07-10 /tmp/demo_key.pub
./scripts/provision.sh requests/req-001.json

# Créer une deuxième VM dans groupe-c (CIDR : 192.168.20.0/24)
ssh-keygen -t ed25519 -f /tmp/demo_key2 -N ""
./scripts/new_request.sh req-002 bob groupe-c 2026-07-10 /tmp/demo_key2.pub
./scripts/provision.sh requests/req-002.json

# Prouver l'isolation réseau (CIDRs différents → pas de route)
./scripts/test_isolation.sh req-001 req-002 /tmp/demo_key

# Tester la destruction automatique
./scripts/new_request.sh req-003 charlie groupe-b 2020-01-01 /tmp/demo_key.pub
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
  "group": "groupe-b",
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
    "group": "groupe-b",
    "template": "ubuntu-dev",
    "end_date": "2026-07-10",
    "floating_ip": "195.15.196.105",
    "status": "up"
  }
]
```

---

## Sécurité

- **SSH par clé uniquement** : `PasswordAuthentication no`, `PermitRootLogin no` (cloud-init)
- **Utilisateur `student`** sans sudo, clé injectée par cloud-init
- **Isolation réseau** : un réseau OpenStack privé par groupe avec CIDR unique — pas de route entre groupes
- **Aucune VM sans date de fin** : refus côté portail ET côté `provision.sh`
- **Credentials** : `openrc-auto.sh` dans `.gitignore`, jamais commité

---

## Destruction automatique

`scripts/destroy_expired.sh` tourne en cron toutes les 10 minutes sur la VM plateforme :

```
*/10 * * * * /home/ubuntu/hackathon-platform/scripts/destroy_expired.sh
```

Chaque destruction est tracée dans `logs/destructions.log`. OpenTofu détruit automatiquement pour chaque VM expirée : l'instance, le port réseau, la floating IP (libérée → plus facturée), et la keypair.

---

## Limites connues (MVP 3 jours)

| Limite | Recommandation production |
|--------|--------------------------|
| État Terraform local sur la VM plateforme | Backend distant (OpenStack Swift, Terraform Cloud) |
| Credentials en fichier plat | HashiCorp Vault ou OpenStack Barbican |
| Pas de SSO O365/OIDC | Intégration OIDC avec Microsoft Entra ID |
| Coûts estimés indicatifs | API de facturation Infomaniak ou Ceilometer |
| Pas de monitoring Prometheus/Grafana | Stack Prometheus + Grafana + node_exporter |
| Flask en mode debug | gunicorn + `debug=False` en production |
| CIDRs stables à l'ajout, instables à la suppression d'un groupe | Définir les CIDRs explicitement dans `variables.tf` |

---

*Hackathon Juillet 2026 — Geneva Institute of Technology × Satom IT & Learning Solutions*
