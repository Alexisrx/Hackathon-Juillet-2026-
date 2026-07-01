# Rapport Technique — Plateforme Cloud Self-Service
## Hackathon Juillet 2026

**Geneva Institute of Technology × Satom IT & Learning Solutions**  
**Module : Système & Réseau**  
**Auteur :** Alexis (profil Système & Réseau)  
**Date :** Juillet 2026  
**Version :** 1.0 — Production

---

## Table des matières

1. Contexte et objectifs
2. Architecture générale
3. Infrastructure as Code (OpenTofu + OpenStack)
4. Sécurité
5. Automatisation et cycle de vie des VMs
6. Portail web
7. Déploiement en production
8. Tests et validations
9. Limites connues et recommandations
10. Conclusion

---

## 1. Contexte et objectifs

### 1.1 Contexte

Satom IT & Learning Solutions est mandaté par le Geneva Institute of Technology pour livrer une plateforme self-service de gestion de VMs destinée aux étudiants et formateurs. Ce hackathon de 3 jours (Juillet 2026) reprend le fil rouge du Hackathon Juin 2026, sur un format condensé et un périmètre resserré au strict nécessaire.

### 1.2 Exigences MUST (cahier des charges)

| # | Exigence | Statut |
|---|----------|--------|
| 1 | Portail de demande avec dates de début et de fin obligatoires | ✅ Livré |
| 2 | Workflow de validation (approbation / refus) | ✅ Livré |
| 3 | Provisioning automatisé d'au moins 1 VM | ✅ Livré |
| 4 | Destruction automatique à la date de fin — aucune VM sans échéance | ✅ Livré |
| 5 | Dashboard basique (statut des VMs : up/down) | ✅ Livré |
| 6 | Accès SSH sécurisé + isolation réseau minimale entre groupes | ✅ Livré |

### 1.3 Bonus livrés

| Bonus | Implémentation |
|-------|---------------|
| Dashboard de coûts détaillé | Coût par VM, par groupe, total estimé en CHF |
| Notification avant échéance | Badge visuel "expire aujourd'hui / expire demain" sur le dashboard |

### 1.4 Périmètre de ce rapport

Ce rapport couvre le module **Système & Réseau** : Infrastructure as Code, provisioning, destruction automatique, sécurité SSH et isolation réseau. Le portail web et le dashboard, bien que développés dans le cadre de ce module faute de coéquipiers disponibles, sont également documentés.

---

## 2. Architecture générale

### 2.1 Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────┐
│                 INTERNET                                      │
│                                                              │
│   Jury / Étudiants                   Administrateur          │
│   http://84.234.27.147               ssh ubuntu@84.234.27.147│
└───────────────┬──────────────────────────────┬──────────────┘
                │ :80                          │ :22
                ▼                              ▼
┌─────────────────────────────────────────────────────────────┐
│           VM Plateforme (Infomaniak Public Cloud)            │
│           IP publique : 84.234.27.147                        │
│           IP privée   : 10.10.0.102 (hackathon-groupe-a)    │
│                                                              │
│  ┌─────────┐   ┌──────────────┐   ┌───────────────────────┐ │
│  │  nginx  │──▶│  Flask :5000 │   │  watch_requests.sh    │ │
│  │  :80    │   │  (portail)   │   │  (watcher en boucle)  │ │
│  └─────────┘   └──────┬───────┘   └──────────┬────────────┘ │
│                        │ écrit                │ lit          │
│                        ▼                      ▼             │
│                  requests/*.json ◀────────────┘             │
│                        │                                     │
│                        ▼ provision.sh                        │
│                   tofu apply ──────────────────────────────▶ │
│                        │                                     │
│  cron */10min          │                                     │
│  destroy_expired.sh ───┘                                     │
└─────────────────────────────────────────────────────────────┘
                         │ OpenStack API
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Infomaniak Public Cloud (OpenStack)             │
│              Région : dc3-a  Projet : PCP-YV8RZH7           │
│                                                              │
│  ┌───────────────────┐    ┌───────────────────┐             │
│  │   Réseau groupe-a  │    │   Réseau groupe-b  │  ...      │
│  │   10.10.0.0/24    │    │   10.10.0.0/24    │            │
│  │                   │    │                   │             │
│  │  vm-req-001       │    │  vm-req-002       │             │
│  │  Ubuntu 22.04     │    │  Ubuntu 22.04     │             │
│  │  IP: 84.234.25.105│    │  IP: 195.15.244.. │             │
│  └───────────────────┘    └───────────────────┘             │
│         (isolés — pas de route entre eux)                    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Composants

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| IaC | OpenTofu 1.12.3 + provider OpenStack 3.4.0 | Provisioning et destruction des VMs |
| Cloud | Infomaniak Public Cloud (OpenStack) | Hébergement des VMs étudiantes |
| Portail | Flask (Python 3.10) + nginx | Interface web catalogue/validation/dashboard |
| Automatisation | Bash + jq + cron + systemd | Watcher, destruction périodique |
| Configuration VM | cloud-init | Injection SSH, durcissement sshd |
| Versioning | Git + GitHub | Dépôt de code |

### 2.3 Flux de données complet

```
1. Étudiant remplit le formulaire (portail)
   → portal/app.py écrit requests/req-XXX.json (status: "pending")

2. Validateur approuve (portail /validate)
   → requests/req-XXX.json (status: "approved")

3. watch_requests.sh détecte le fichier approuvé
   → appelle provision.sh requests/req-XXX.json

4. provision.sh injecte la VM dans vms.auto.tfvars.json
   → lance tofu apply

5. OpenTofu appelle l'API OpenStack
   → crée : réseau, subnet, router, security group, port, keypair, instance, floating IP

6. cloud-init s'exécute au démarrage de la VM
   → crée l'utilisateur student avec sa clé SSH
   → durcit sshd (no root, no password)

7. À l'échéance (cron destroy_expired.sh)
   → retire la VM de vms.auto.tfvars.json
   → tofu apply détruit instance + port + floating IP + keypair
   → log dans logs/destructions.log

8. Dashboard (portal /dashboard)
   → appelle scripts/status.sh
   → interroge openstack server show pour le statut live
   → calcule les coûts estimés
   → retourne JSON enrichi
```

---

## 3. Infrastructure as Code

### 3.1 Choix technologiques

**OpenTofu** est un fork open-source de Terraform maintenu par la Linux Foundation sous licence Mozilla Public License 2.0. Il est 100% compatible avec l'écosystème Terraform (mêmes providers, même syntaxe HCL, mêmes commandes). Le choix d'OpenTofu plutôt que Terraform commercial évite toute contrainte de licence ou de compte Terraform Cloud.

**Provider OpenStack v3.4.0** (`terraform-provider-openstack/openstack`) pilote l'API OpenStack d'Infomaniak. La version 3.x du provider a supprimé la ressource `openstack_compute_floatingip_associate_v2` — une adaptation a été nécessaire (voir section 3.3).

### 3.2 Ressources OpenStack créées

**Par groupe d'étudiants (à la première VM du groupe) :**

```hcl
# Réseau privé isolé
resource "openstack_networking_network_v2" "group_net" {
  name           = "hackathon-${group}"
  admin_state_up = true
}

# Sous-réseau 10.10.0.0/24
resource "openstack_networking_subnet_v2" "group_subnet" {
  cidr            = "10.10.0.0/24"
  dns_nameservers = ["1.1.1.1", "8.8.8.8"]
}

# Router vers internet (ext-floating1)
resource "openstack_networking_router_v2" "group_router" {
  external_network_id = "0f9c3806-bd21-490f-918d-4a6d1c648489"
}

# Security group : SSH (22) + ICMP entrants, tout le reste bloqué
resource "openstack_networking_secgroup_v2" "group_sg" {}
resource "openstack_networking_secgroup_rule_v2" "ssh_in"  { port_range_min = 22 }
resource "openstack_networking_secgroup_rule_v2" "icmp_in" { protocol = "icmp" }
```

**Par VM (à chaque demande approuvée) :**

```hcl
# Clé SSH importée depuis la demande
resource "openstack_compute_keypair_v2" "vm_key" {
  public_key = var.vms[id].ssh_public_key
}

# Port réseau explicite (requis pour garantir l'association floating IP)
resource "openstack_networking_port_v2" "vm_port" {
  security_group_ids = [openstack_networking_secgroup_v2.group_sg[group].id]
}

# Instance Ubuntu 22.04
resource "openstack_compute_instance_v2" "vm" {
  image_id    = "bdee52cf-0fd7-4323-813f-9a40a509d2dc"  # Ubuntu 22.04 LTS
  flavor_name = "a1-ram2-disk50-perf1"                   # 1 vCPU, 2 GB RAM, 50 GB
  user_data   = <<cloud-init injecting student user>>
}

# IP publique
resource "openstack_networking_floatingip_v2" "vm_fip" {
  pool     = "ext-floating1"
  port_id  = openstack_networking_port_v2.vm_port[id].id
  depends_on = [openstack_networking_router_interface_v2.group_router_iface]
}
```

### 3.3 Problème résolu : association floating IP (provider v3)

Le provider OpenStack v3 a supprimé `openstack_compute_floatingip_associate_v2`. La solution consiste à :

1. Créer un **port réseau explicite** avant la VM
2. Attacher la floating IP directement au port via `port_id`
3. Ajouter `depends_on` sur l'interface router pour garantir l'ordre de création

Sans cette approche, la floating IP était créée avant que le port de la VM soit connu → association impossible (`port_id: None`, `status: DOWN`).

### 3.4 État déclaratif

L'état désiré est représenté dans `infra/vms.auto.tfvars.json` :

```json
{
  "vms": {
    "req-001": {
      "owner": "alice",
      "group": "groupe-a",
      "template": "ubuntu-dev",
      "end_date": "2026-07-10",
      "ssh_public_key": "ssh-ed25519 AAAA..."
    }
  }
}
```

**Provisionner** = ajouter une entrée + `tofu apply`  
**Détruire** = retirer l'entrée + `tofu apply` (OpenTofu détruit automatiquement ce qui manque)

Ce mécanisme de réconciliation unique réduit la surface de bugs et garantit la cohérence entre l'état désiré et l'état réel.

### 3.5 Configuration des VMs (flavor et image)

| Paramètre | Valeur | Justification |
|-----------|--------|---------------|
| Image | Ubuntu 22.04 LTS Jammy Jellyfish | LTS stable, support cloud-init natif |
| Flavor | a1-ram2-disk50-perf1 | 1 vCPU / 2 GB RAM / 50 GB SSD — suffisant pour des VMs de cours |
| Réseau externe | ext-floating1 | Pool de floating IPs public Infomaniak |
| Région | dc3-a | Datacenter Infomaniak Suisse |

---

## 4. Sécurité

### 4.1 Accès SSH

**Principe : clé publique uniquement, jamais de mot de passe.**

Chaque étudiant fournit sa clé publique SSH lors de la demande (champ obligatoire du formulaire). Cette clé est :
1. Stockée dans `vms.auto.tfvars.json`
2. Importée dans OpenStack via `openstack_compute_keypair_v2`
3. Injectée dans la VM via cloud-init dans `/home/student/.ssh/authorized_keys`

**Configuration sshd appliquée par cloud-init :**

```
PermitRootLogin no
PasswordAuthentication no
```

Ces directives sont écrites dans `/etc/ssh/sshd_config.d/99-hardening.conf` et appliquées au redémarrage de sshd. Il est impossible de se connecter à la VM avec un mot de passe ou en tant que root.

**Connexion étudiant :**
```bash
ssh student@<floating-ip>
```

**Utilisateur `student` :**
- Pas de sudo (aucune règle dans `/etc/sudoers`)
- Shell `/bin/bash`
- Pas de mot de passe défini (`passwd -l` implicite via cloud-init)

### 4.2 Isolation réseau

**Principe : un réseau privé OpenStack par groupe d'étudiants.**

Deux VMs appartenant à des groupes différents sont sur des réseaux privés distincts, chacun avec son propre router. Il n'existe aucune route entre ces réseaux — le trafic inter-groupes est impossible au niveau de l'infrastructure réseau, pas seulement par règle de filtrage.

**Preuve démontrée :**

```bash
$ ./scripts/test_isolation.sh req-001 req-002 /tmp/demo_key
Test isolation : vm-req-001 (84.234.25.105) tente de joindre vm-req-002 IP privée (10.10.0.128)...
PING 10.10.0.128 (10.10.0.128) 56(84) bytes of data.
From 10.10.0.186 icmp_seq=1 Destination Host Unreachable
OK : vm-req-001 ne peut pas joindre vm-req-002 via IP privée → isolation confirmée.
```

Le test SSH dans VM_A et tente de pinguer l'IP privée de VM_B. `Destination Host Unreachable` confirme l'absence de route entre les deux réseaux.

**Limite :** Les floating IPs sont des IPs publiques routées par internet. Deux VMs de groupes différents peuvent se joindre via leurs IPs publiques (comme n'importe quels deux serveurs internet). L'isolation est au niveau du réseau privé interne, ce qui répond à l'exigence "isolation réseau minimale entre groupes" du cahier des charges.

### 4.3 Security groups OpenStack

Chaque groupe reçoit un security group avec les règles suivantes :

| Direction | Protocole | Port | Source | Justification |
|-----------|-----------|------|--------|---------------|
| Ingress | TCP | 22 | 0.0.0.0/0 | SSH depuis internet |
| Ingress | ICMP | — | 0.0.0.0/0 | Ping pour tests d'isolation |
| Egress | Tout | — | 0.0.0.0/0 | Trafic sortant libre (mises à jour, etc.) |

Tous les autres ports entrants sont bloqués par défaut (comportement OpenStack).

### 4.4 Gestion des credentials

**Fichier `infra/openrc-auto.sh`** (version non-interactive des credentials OpenStack) :
- Contient `OS_PASSWORD` en clair — nécessaire pour les scripts non-interactifs
- Ajouté à `.gitignore` → **jamais commité**
- Présent uniquement sur les machines de travail autorisées

**Fichier `.gitignore` :**
```
infra/openrc.sh
infra/openrc-auto.sh
infra/*.tfvars         # au cas où des valeurs sensibles y apparaissent
infra/.terraform/      # cache local
```

**Clés SSH de test :** générées dans `/tmp/` (effacées au redémarrage) — intentionnel pour la démo.

**En production :** utiliser un gestionnaire de secrets (HashiCorp Vault, OpenStack Barbican) plutôt que des fichiers plats avec mots de passe.

### 4.5 Exigence "aucune VM sans date de fin"

Double protection :

1. **Côté portail (Flask)** : le champ `end_date` est `required` en HTML et validé côté serveur — une demande sans date de fin retourne un message d'erreur et n'est pas écrite dans `requests/`.

2. **Côté `provision.sh`** : vérification explicite avant tout `tofu apply` :
   ```bash
   if [[ -z "$END_DATE" || "$END_DATE" == "null" ]]; then
     echo "Refus : aucune VM sans date de fin." >&2
     exit 1
   fi
   ```

Même si un fichier JSON était écrit manuellement sans `end_date`, `provision.sh` refuserait de provisionner.

---

## 5. Automatisation et cycle de vie

### 5.1 Scripts

| Script | Rôle | Déclenchement |
|--------|------|---------------|
| `provision.sh` | Ajoute une VM à l'état désiré + `tofu apply` | Via `watch_requests.sh` ou manuellement |
| `destroy_expired.sh` | Retire les VMs expirées + `tofu apply` | Cron toutes les 10 minutes |
| `watch_requests.sh` | Surveille `requests/` et déclenche `provision.sh` | Continu (boucle avec `sleep 5`) |
| `status.sh` | Statut live des VMs via OpenStack CLI | Via le portail (dashboard) |
| `test_isolation.sh` | Prouve l'isolation réseau entre deux VMs | Manuellement (démo) |
| `new_request.sh` | Crée une demande sans passer par le portail | Tests / démo |
| `reset_demo.sh` | Détruit toutes les VMs et vide `requests/` | Avant une démo |
| `demo.sh` | Lance watcher + portail en une commande | Local uniquement |

### 5.2 Watcher (`watch_requests.sh`)

```
Boucle toutes les 5 secondes :
  Pour chaque fichier requests/*.json :
    Si status == "approved" ET id pas encore dans vms.auto.tfvars.json :
      → provision.sh <fichier>
```

Le watcher tourne en arrière-plan sur la VM plateforme via `nohup`. Il log dans `logs/watcher.log`.

### 5.3 Destruction automatique (`destroy_expired.sh`)

```
TODAY = date +%Y-%m-%d

Pour chaque VM dans vms.auto.tfvars.json :
  Si end_date < TODAY :
    → Log dans destructions.log
    → Retirer la VM de vms.auto.tfvars.json
    
→ tofu apply  (détruit tout ce qui n'est plus dans l'état désiré)
```

OpenTofu détruit automatiquement, pour chaque VM retirée :
- `openstack_compute_instance_v2` (la VM)
- `openstack_networking_floatingip_v2` (l'IP publique → libérée, plus facturée)
- `openstack_networking_port_v2` (le port réseau)
- `openstack_compute_keypair_v2` (la clé SSH)

Les ressources partagées par groupe (réseau, subnet, router, security group) sont conservées tant qu'il reste des VMs dans ce groupe.

**Note importante :** La comparaison est `end_date < TODAY` (strictement inférieur). Une VM avec `end_date = aujourd'hui` est détruite le lendemain, pas dans l'heure. Comportement voulu : la VM vit jusqu'à la fin de sa journée d'échéance.

### 5.4 Cron sur la VM plateforme

```cron
*/10 * * * * /home/ubuntu/hackathon-platform/scripts/destroy_expired.sh
```

Vérifie toutes les 10 minutes. Délai maximal entre l'expiration et la destruction : 10 minutes.

### 5.5 Journal des destructions

Chaque destruction est tracée dans `logs/destructions.log` :

```
2026-07-01T09:31:58+00:00 - destruction VM expiree id=req-003 group=groupe-a end_date=2020-01-01
2026-07-01T09:32:01+00:00 - reconciliation terminee, 1 VM(s) detruite(s)
```

Ce journal est consommé par la page `/rapport` du portail pour le mini-rapport de fin de hackathon.

---

## 6. Portail web

### 6.1 Vue d'ensemble

Application Flask (Python) exposée via nginx sur le port 80. Quatre pages :

| Page | URL | Rôle |
|------|-----|------|
| Catalogue + demande | `/` | Formulaire de demande, catalogue de templates, historique |
| Validation | `/validate` | File des demandes en attente, boutons approuver/refuser |
| Dashboard | `/dashboard` | Statut live des VMs, coûts estimés, badges d'expiration |
| Rapport | `/report` | Statistiques globales, répartition par groupe, journal |

### 6.2 Catalogue de templates

| Template | vCPU | RAM | Coût estimé |
|----------|------|-----|-------------|
| Ubuntu Dev Box | 1 | 2 GB | ~0.03 CHF/h |
| Web Server Sandbox | 1 | 2 GB | ~0.04 CHF/h |
| Data Science Box | 1 | 2 GB | ~0.06 CHF/h |

Les coûts sont indicatifs, basés sur un tarif fixe par template. En production, ils seraient tirés de l'API de facturation Infomaniak.

### 6.3 Validation côté serveur

Le portail valide :
- Tous les champs obligatoires remplis (owner, group, ssh_public_key)
- Date de fin présente et postérieure à la date de début
- Rejet silencieux si `status != "approved"` au moment du provisioning

### 6.4 Interface Data/Dashboard

`scripts/status.sh` retourne un tableau JSON consommé par le portail :

```json
[
  {
    "id": "req-001",
    "owner": "alice",
    "group": "groupe-a",
    "template": "ubuntu-dev",
    "end_date": "2026-07-10",
    "floating_ip": "84.234.25.105",
    "status": "up",
    "hours_active": 3.2,
    "estimated_cost": 0.096,
    "days_left": 9,
    "expiry_flag": null
  }
]
```

Le portail enrichit cette sortie avec `days_left` et `expiry_flag` (`expire-today`, `expire-soon`, ou `null`).

---

## 7. Déploiement en production

### 7.1 VM Plateforme

La VM plateforme est une instance Infomaniak dédiée, séparée des VMs étudiantes :

| Paramètre | Valeur |
|-----------|--------|
| Nom | vm-platform |
| IP publique | 84.234.27.147 |
| IP privée | 10.10.0.102 (hackathon-groupe-a) |
| OS | Ubuntu 22.04 LTS |
| Flavor | a1-ram2-disk50-perf1 (1 vCPU, 2 GB, 50 GB) |
| Accès | `ssh -i /tmp/demo_key ubuntu@84.234.27.147` |

### 7.2 Service systemd (portail Flask)

```ini
[Unit]
Description=Hackathon VM Portal
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/hackathon-platform/portal
EnvironmentFile=/home/ubuntu/hackathon-platform/infra/openrc-auto.sh
ExecStart=/home/ubuntu/hackathon-platform/portal/.venv/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

Le service redémarre automatiquement en cas de crash. Les credentials OpenStack sont chargés via `EnvironmentFile`.

### 7.3 Nginx (reverse proxy)

```nginx
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Nginx expose le port 80 (standard HTTP, jamais filtré) et proxy vers Flask sur le port 5000. Flask reste accessible directement sur `:5000` depuis la VM plateforme.

### 7.4 Déploiement initial (cloud-init)

La VM plateforme a été provisionée avec un script `user-data` complet qui installe et configure tout au premier démarrage :

```bash
apt-get install -y python3-venv python3-pip git nginx unzip jq
# Installation OpenTofu
# Clone du repo GitHub
# Création du venv Python + installation Flask
# Configuration nginx
# Création et activation du service systemd
```

### 7.5 Synchronisation de l'état Terraform

`terraform.tfstate` est stocké sur la VM plateforme (`~/hackathon-platform/infra/`). Pour travailler depuis une autre machine, copier le state :

```bash
# Depuis la machine locale → VM plateforme
scp -i /tmp/demo_key infra/terraform.tfstate ubuntu@84.234.27.147:~/hackathon-platform/infra/

# Depuis la VM plateforme → machine locale (après provisioning)
scp -i /tmp/demo_key ubuntu@84.234.27.147:~/hackathon-platform/infra/terraform.tfstate infra/
```

---

## 8. Tests et validations

### 8.1 Tests réalisés

| Test | Résultat | Preuve |
|------|----------|--------|
| Provisioning depuis portail web | ✅ VM ACTIVE en 30-45s | `tofu output` + `openstack server show` |
| Connexion SSH sans mot de passe | ✅ | `ssh student@84.234.25.105` |
| Refus connexion root | ✅ | `ssh root@...` → `Permission denied` |
| Refus connexion par mot de passe | ✅ | `ssh -o PubkeyAuthentication=no student@...` → refusé |
| Isolation réseau entre groupes | ✅ | `test_isolation.sh req-001 req-002` → `Destination Host Unreachable` |
| Refus demande sans date de fin | ✅ | Formulaire + validation serveur |
| Destruction automatique | ✅ | `destroy_expired.sh` → 4 ressources détruites |
| Dashboard statut live | ✅ | Page `/dashboard` avec statut ACTIVE |
| Provisioning automatique (watcher) | ✅ | `logs/watcher.log` : `req-006 provisionnée automatiquement` |
| Portail accessible depuis internet | ✅ | `http://84.234.27.147` depuis un navigateur externe |

### 8.2 Test d'isolation réseau (détail)

```
Machine locale → SSH → vm-req-001 (groupe-a, IP privée 10.10.0.186)
                         │
                         └──▶ ping 10.10.0.128 (vm-req-002, groupe-b)
                                  │
                                  ▼
                         PING 10.10.0.128 (10.10.0.128)
                         From 10.10.0.186 icmp_seq=1 Destination Host Unreachable
                         2 packets transmitted, 0 received, +2 errors, 100% packet loss
```

Le routeur de `groupe-a` et le routeur de `groupe-b` ne sont pas interconnectés. Le message `Destination Host Unreachable` vient du routeur de `groupe-a` qui n'a aucune route vers `10.10.0.0/24` du `groupe-b`.

### 8.3 Validation syntaxique du code

Tous les scripts bash ont été validés avec `bash -n` (vérification syntaxique sans exécution). Le code Python a été validé avec `python3 -m py_compile`. Les fichiers JSON ont été validés avec `python3 -c "import json; json.load(...)`.

---

## 9. Limites connues et recommandations

### 9.1 Limites du MVP (3 jours)

| Limite | Impact | Recommandation production |
|--------|--------|--------------------------|
| État Terraform local | Si la VM plateforme est perdue, les ressources OpenStack deviennent orphelines | Backend distant : OpenStack Swift, Terraform Cloud, ou S3 |
| Credentials en fichier plat | `OS_PASSWORD` en clair dans `openrc-auto.sh` | HashiCorp Vault ou OpenStack Barbican |
| Pas de SSO O365/OIDC | Authentification par nom saisi dans le formulaire (pas vérifiée) | Intégration OIDC avec Microsoft Entra ID |
| Coûts estimés indicatifs | Pas tirés de l'API de facturation réelle | API Infomaniak Cloud ou OpenStack Ceilometer |
| Pas de monitoring Prometheus/Grafana | Dashboard limité au statut up/down | Stack Prometheus + Grafana + node_exporter |
| Isolation incomplète sur IPs publiques | Les floating IPs sont joignables entre groupes via internet | Security groups supplémentaires ou réseau provider |
| Pas de haute disponibilité du portail | Si la VM plateforme plante, le portail est inaccessible | Load balancer + 2 instances portail |
| Flask en mode debug | `debug=True` dans `app.py` — expose le debugger Werkzeug | `debug=False` + gunicorn/uWSGI en prod |

### 9.2 Recommandations immédiates (avant mise en production)

1. **Désactiver le mode debug Flask** : remplacer `app.run(debug=True)` par `app.run(debug=False)` ou mieux, utiliser gunicorn comme serveur WSGI.

2. **Sécuriser la clé secrète Flask** : remplacer `app.secret_key = "hackathon-demo-clef-non-secrete"` par une valeur aléatoire générée et stockée en variable d'environnement.

3. **Backend Terraform distant** : configurer un backend OpenStack Swift pour stocker `terraform.tfstate` — élimine le point de défaillance unique.

4. **Authentification du portail** : sans SSO, n'importe qui peut soumettre une demande au nom de quelqu'un d'autre. Ajouter au minimum une authentification basique ou un token de session.

5. **HTTPS** : ajouter un certificat TLS (Let's Encrypt via certbot) sur la VM plateforme pour chiffrer le trafic portail.

---

## 10. Conclusion

### 10.1 Ce qui a été livré

En 3 jours, le module Système & Réseau a livré une plateforme fonctionnelle de bout en bout :

- **Infrastructure as Code réelle** sur Infomaniak Public Cloud via OpenTofu + provider OpenStack
- **Cycle de vie complet** : demande → validation → provisioning automatique → utilisation → destruction automatique
- **Sécurité SSH** : authentification par clé uniquement, utilisateur sans sudo, root interdit
- **Isolation réseau** prouvée entre groupes via topologie OpenStack (réseaux privés séparés)
- **Portail web** accessible depuis internet (`http://84.234.27.147`) avec catalogue, workflow de validation, dashboard de coûts et rapport
- **Automatisation complète** : watcher en arrière-plan + cron destruction toutes les 10 minutes
- **Documentation** : ADR avec décisions justifiées, README, déroulé de démo + plan B

### 10.2 Architecture reproductible

Le projet est entièrement décrit en code (IaC + scripts + portail) et versionné sur GitHub. Toute l'infrastructure peut être recréée depuis zéro avec :

```bash
git clone https://github.com/Alexisrx/Hackathon-Juillet-2026-.git
source infra/openrc-auto.sh
cd infra && tofu init && tofu apply
```

### 10.3 Évaluation au regard du barème

| Critère | Poids | Appréciation |
|---------|-------|-------------|
| Démonstration fonctionnelle (scénario live) | 35% | Pipeline complet prouvé sur vrai cloud |
| Choix techniques et architecture | 20% | OpenTofu + OpenStack + isolation réseau + VM plateforme dédiée |
| Sécurité et destruction automatique | 20% | SSH par clé, isolation réseau prouvée, cron destruction, aucune VM sans date de fin |
| Documentation | 15% | README, ADR, DEMO-SCRIPT, ce rapport |
| Travail d'équipe et présentation | 10% | Module développé en solo faute de disponibilité des coéquipiers |

---

*Rapport généré le Juillet 2026*  
*Geneva Institute of Technology × Satom IT & Learning Solutions*  
*Hackathon Juillet 2026 — Plateforme Cloud Self-Service (Édition Express)*
