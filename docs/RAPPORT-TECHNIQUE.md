# Rapport Technique — Plateforme Cloud Self-Service
## Hackathon Juillet 2026

**Geneva Institute of Technology × Satom IT & Learning Solutions**  
**Module : Système & Réseau**  
**Auteur :** Alexis (profil Système & Réseau)  
**Date :** Juillet 2026 — Version finale

---

## Table des matières

1. Contexte et objectifs
2. Architecture générale
3. Infrastructure as Code (OpenTofu + OpenStack)
4. Isolation réseau et CIDRs uniques
5. Sécurité
6. Automatisation et cycle de vie des VMs
7. Portail web
8. Déploiement en production
9. Tests et validations
10. Limites connues et recommandations
11. Conclusion

---

## 1. Contexte et objectifs

### 1.1 Contexte

Satom IT & Learning Solutions est mandaté par le Geneva Institute of Technology pour livrer une plateforme self-service de gestion de VMs destinée aux étudiants et formateurs. Ce hackathon de 3 jours reprend le fil rouge du Hackathon Juin 2026 sur un format condensé.

### 1.2 Exigences MUST

| # | Exigence | Statut |
|---|----------|--------|
| 1 | Portail de demande avec dates de début/fin obligatoires | ✅ |
| 2 | Workflow de validation (approbation / refus) | ✅ |
| 3 | Provisioning automatisé d'au moins 1 VM | ✅ |
| 4 | Destruction automatique à la date de fin | ✅ |
| 5 | Dashboard basique (statut up/down) | ✅ |
| 6 | Accès SSH sécurisé + isolation réseau entre groupes | ✅ |

### 1.3 Bonus livrés

| Bonus | Implémentation |
|-------|---------------|
| Dashboard de coûts détaillé | Par VM + par groupe + total estimé CHF |
| Notification avant échéance | Badge visuel sur le dashboard |

---

## 2. Architecture générale

### 2.1 Vue d'ensemble

```
INTERNET
    │
    ├── Jury/Étudiants → http://84.234.27.147 (:80)
    └── Admin → ssh ubuntu@84.234.27.147 (:22)
                         │
            ┌────────────▼───────────────┐
            │    VM Plateforme           │
            │    nginx :80               │
            │    Flask :5000             │
            │    watch_requests.sh       │
            │    destroy_expired (cron)  │
            └────────────┬───────────────┘
                         │ OpenStack API
            ┌────────────▼───────────────┐
            │  Infomaniak Public Cloud   │
            │                            │
            │  groupe-b  192.168.10.0/24 │
            │  groupe-c  192.168.20.0/24 │
            │  groupe-d  192.168.30.0/24 │
            │  ...       (isolés)        │
            └────────────────────────────┘
```

### 2.2 Flux complet

```
1. Étudiant remplit le formulaire → requests/req-XXX.json (pending)
2. Validateur approuve → status: approved
3. watch_requests.sh détecte → appelle provision.sh
4. provision.sh → vms.auto.tfvars.json + tofu apply
5. OpenStack : réseau (CIDR unique) + subnet + router + sg + port + keypair + VM + floating IP
6. cloud-init : crée student, injecte SSH key, durcit sshd
7. Cron destroy_expired.sh : retire VM expirée de tfvars + tofu apply
8. dashboard : status.sh → JSON → Flask → /dashboard
```

---

## 3. Infrastructure as Code

### 3.1 Choix technologiques

**OpenTofu v1.12.3** — fork open-source de Terraform (licence MPL), 100% compatible avec l'écosystème Terraform. Zéro contrainte de licence, installation immédiate.

**Provider OpenStack v3.4.0** — pilote l'API OpenStack d'Infomaniak. La version 3.x a supprimé `openstack_compute_floatingip_associate_v2`, ce qui a nécessité l'adoption de ports réseau explicites (voir section 3.3).

### 3.2 Ressources OpenStack

**Par groupe (créées à la première VM du groupe) :**
- `openstack_networking_network_v2` — réseau privé isolé
- `openstack_networking_subnet_v2` — CIDR unique `192.168.X0.0/24`
- `openstack_networking_router_v2` — router vers `ext-floating1`
- `openstack_networking_router_interface_v2`
- `openstack_networking_secgroup_v2` — SSH + ICMP entrants
- `openstack_networking_secgroup_rule_v2` (x2)

**Par VM (par demande approuvée) :**
- `openstack_compute_keypair_v2` — clé SSH de l'étudiant
- `openstack_networking_port_v2` — port réseau explicite
- `openstack_compute_instance_v2` — Ubuntu 22.04, `a1-ram2-disk50-perf1`
- `openstack_networking_floatingip_v2` — IP publique SSH

### 3.3 Port réseau explicite (solution provider v3)

Le provider OpenStack v3 a supprimé la ressource d'association floating IP. Solution : créer un port réseau explicite avant la VM et y attacher directement la floating IP :

```hcl
resource "openstack_networking_port_v2" "vm_port" {
  network_id         = openstack_networking_network_v2.group_net[group].id
  security_group_ids = [openstack_networking_secgroup_v2.group_sg[group].id]
  fixed_ip { subnet_id = openstack_networking_subnet_v2.group_subnet[group].id }
}

resource "openstack_networking_floatingip_v2" "vm_fip" {
  port_id    = openstack_networking_port_v2.vm_port[id].id
  depends_on = [openstack_networking_router_interface_v2.group_router_iface]
}
```

Le `depends_on` est critique : sans lui, OpenStack retourne `ExternalGatewayForFloatingIPNotFound` car le subnet n'est pas encore routé.

### 3.4 État déclaratif

```json
{
  "vms": {
    "req-001": {
      "owner": "alice", "group": "groupe-b", "template": "ubuntu-dev",
      "end_date": "2026-07-10", "ssh_public_key": "ssh-ed25519 ..."
    }
  }
}
```

Provisionner = ajouter + `tofu apply`. Détruire = retirer + `tofu apply`.

---

## 4. Isolation réseau et CIDRs uniques

### 4.1 Problème initial

Avec tous les groupes sur `10.10.0.0/24`, un bastion connecté à plusieurs réseaux ne peut pas router sans ambiguïté :

```
Bastion (eth0: 10.10.0.5/24 sur groupe-a)
       (eth1: 10.10.0.5/24 sur groupe-b)

ping 10.10.0.128 → quelle interface ? groupe-a ou groupe-b ?
→ Ambiguïté de routage → comportement indéfini
```

### 4.2 Solution : CIDRs uniques par position alphabétique

```hcl
locals {
  groups_list = sort(tolist(toset([for k, v in var.vms : v.group])))
  group_cidrs = {
    for idx, g in local.groups_list :
    g => "192.168.${(idx + 1) * 10}.0/24"
  }
}
```

**Résultat :**
```
groupe-b (idx=0) → 192.168.10.0/24  ✅ actif
groupe-c (idx=1) → 192.168.20.0/24
groupe-d (idx=2) → 192.168.30.0/24
...jusqu'à groupe-z (idx=24) → 192.168.250.0/24
```

**Comportement à l'ajout :** stable — le nouveau groupe prend le CIDR suivant, les existants ne bougent pas.  
**Comportement à la suppression :** ⚠️ les groupes suivants changent d'index → CIDR shift. En production, déclarer les CIDRs explicitement.

### 4.3 Isolation prouvée

Deux VMs dans des groupes différents (CIDRs distincts, routers distincts) :

```
vm-req-001 (192.168.10.186, groupe-b)
  └── ping 192.168.20.128 (vm-req-002, groupe-c)
        └── Destination Host Unreachable ✅
```

Aucune route n'existe entre les réseaux privés — isolation garantie par topologie, pas par règles de filtrage.

---

## 5. Sécurité

### 5.1 Accès SSH

**Principe : clé publique uniquement, jamais de mot de passe.**

Chaque étudiant fournit sa clé publique SSH dans le formulaire. Elle est injectée via cloud-init :

```yaml
#cloud-config
users:
  - name: student
    ssh_authorized_keys:
      - <clé publique>
    shell: /bin/bash
write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
```

L'utilisateur `student` n'a pas de sudo, pas de mot de passe défini. Connexion : `ssh student@<floating-ip>`.

### 5.2 Security groups OpenStack

| Direction | Protocole | Port | Source |
|-----------|-----------|------|--------|
| Ingress | TCP | 22 | 0.0.0.0/0 |
| Ingress | ICMP | — | 0.0.0.0/0 |
| Egress | Tout | — | 0.0.0.0/0 |

Tous les autres ports entrants sont bloqués par défaut.

### 5.3 Aucune VM sans date de fin

Double protection :
1. **Formulaire Flask** : champ `end_date` requis côté HTML et validé côté serveur
2. **`provision.sh`** : vérification explicite avant tout `tofu apply`

```bash
if [[ -z "$END_DATE" || "$END_DATE" == "null" ]]; then
  echo "Refus : aucune VM sans date de fin." >&2; exit 1
fi
```

### 5.4 Gestion des credentials

`infra/openrc-auto.sh` (contient `OS_PASSWORD`) est dans `.gitignore` — jamais commité. Seul un template vide est versionné.

---

## 6. Automatisation et cycle de vie

### 6.1 Scripts

| Script | Rôle | Déclenchement |
|--------|------|---------------|
| `provision.sh` | Ajoute une VM + `tofu apply` | Automatique via watcher |
| `destroy_expired.sh` | Retire VMs expirées + `tofu apply` | Cron toutes les 10 min |
| `watch_requests.sh` | Surveille `requests/` en boucle | Continu sur VM plateforme |
| `status.sh` | Statut live via OpenStack CLI | Appelé par le portail |
| `test_isolation.sh` | Teste isolation SSH+ping | Démo manuelle |
| `new_request.sh` | Crée une demande de test | Tests/démo |
| `reset_demo.sh` | Remet à zéro avant démo | Manuel |

### 6.2 Destruction automatique

```
Cron (*/10 * * * *) → destroy_expired.sh
  ↓
Pour chaque VM : end_date < aujourd'hui ?
  ↓ oui
Retirer de vms.auto.tfvars.json
  ↓
tofu apply → OpenTofu détruit :
  - openstack_compute_instance_v2     (VM)
  - openstack_networking_floatingip_v2 (IP publique libérée → plus facturée)
  - openstack_networking_port_v2       (port réseau)
  - openstack_compute_keypair_v2       (clé SSH)
  ↓
Log dans logs/destructions.log
```

---

## 7. Portail web

### 7.1 Pages

| Page | URL | Rôle |
|------|-----|------|
| Catalogue + demande | `/` | Formulaire, catalogue 3 templates, historique |
| Validation | `/validate` | File des demandes, approuver/refuser |
| Dashboard | `/dashboard` | Statut live, coûts estimés, badges expiration |
| Rapport | `/report` | Stats globales, coûts par groupe, journal |

### 7.2 Catalogue

| Template | Coût estimé |
|----------|-------------|
| Ubuntu Dev Box | ~0.03 CHF/h |
| Web Server Sandbox | ~0.04 CHF/h |
| Data Science Box | ~0.06 CHF/h |

### 7.3 Dashboard enrichi

```json
{
  "id": "req-001", "owner": "alice", "group": "groupe-b",
  "floating_ip": "195.15.196.105", "status": "up",
  "hours_active": 2.5, "estimated_cost": 0.075,
  "days_left": 9, "expiry_flag": null
}
```

`expiry_flag` : `"expire-today"`, `"expire-soon"` (J-1), ou `null`.

---

## 8. Déploiement en production

### 8.1 VM Plateforme

| Paramètre | Valeur |
|-----------|--------|
| IP publique | 84.234.27.147 |
| OS | Ubuntu 22.04 LTS |
| Flavor | a1-ram2-disk50-perf1 |
| Réseau | hackathon-groupe-a (hors IaC, géré manuellement) |

### 8.2 Services actifs

```
nginx           → proxy :80 vers Flask :5000
hackathon-portal → systemd, restart=always
watch_requests  → nohup, arrière-plan
destroy_expired → cron */10 * * * *
```

### 8.3 Cas particulier : réseau groupe-a hors IaC

La VM plateforme est sur le réseau `hackathon-groupe-a`. Pour éviter qu'un `reset_demo.sh` tente de supprimer ce réseau (et perde la connectivité de la plateforme), les ressources `groupe-a` ont été retirées du state Tofu avec `tofu state rm` — elles restent sur Infomaniak mais ne sont plus gérées par l'IaC hackathon.

---

## 9. Tests et validations

| Test | Résultat |
|------|----------|
| Provisioning depuis portail web (req-001, alice, groupe-b) | ✅ VM ACTIVE, IP `195.15.196.105`, CIDR `192.168.10.0/24` |
| Connexion SSH par clé, sans mot de passe | ✅ |
| Refus connexion root | ✅ `Permission denied` |
| Refus demande sans date de fin | ✅ Formulaire + validation serveur |
| Isolation réseau entre groupes (CIDRs distincts) | ✅ `Destination Host Unreachable` |
| Destruction automatique (cron + `tofu apply`) | ✅ 4 ressources supprimées |
| Dashboard statut live | ✅ Page `/dashboard` opérationnelle |
| Provisioning automatique via watcher | ✅ `logs/watcher.log` : req-006 provisionnée automatiquement |
| Portail accessible depuis internet | ✅ `http://84.234.27.147` |

---

## 10. Limites connues et recommandations

| Limite | Impact | Recommandation |
|--------|--------|----------------|
| État Terraform local | Si VM plateforme perdue → ressources orphelines | Backend distant (Swift, Terraform Cloud) |
| Credentials en fichier plat | `OS_PASSWORD` en clair | HashiCorp Vault |
| Pas de SSO O365 | Identité non vérifiée | OIDC avec Microsoft Entra ID |
| Coûts indicatifs | Pas tirés de l'API réelle | API facturation Infomaniak |
| Pas de monitoring Prometheus/Grafana | Dashboard basique | Stack Prometheus + Grafana |
| Flask en mode debug | Expose le debugger Werkzeug | gunicorn + `debug=False` |
| CIDRs instables à suppression de groupe | Subnets recréés | Déclarer les CIDRs explicitement dans `variables.tf` |
| groupe-a hors IaC | Incohérence partielle state/réalité | Migrer VM plateforme sur un réseau dédié géré par l'IaC |

---

## 11. Conclusion

### 11.1 Récapitulatif

En 3 jours, le module Système & Réseau (développé en solo faute de disponibilité des coéquipiers) a livré :

- **Infrastructure as Code réelle** sur Infomaniak Public Cloud (OpenTofu + OpenStack)
- **Cycle de vie complet** : demande → validation → provisioning automatique → utilisation → destruction automatique
- **Isolation réseau robuste** avec CIDRs uniques par groupe (`192.168.X0.0/24`)
- **Sécurité SSH** : clé uniquement, utilisateur sans sudo, root interdit
- **Portail web** accessible depuis internet (`http://84.234.27.147`)
- **Automatisation complète** : watcher + cron destruction
- **Documentation complète** : ADR, README, déroulé démo, rapport

### 11.2 Évaluation au regard du barème

| Critère | Poids | Appréciation |
|---------|-------|-------------|
| Démonstration fonctionnelle | 35% | Pipeline complet prouvé sur vrai cloud Infomaniak |
| Choix techniques et architecture | 20% | OpenTofu + OpenStack + CIDRs uniques + isolation par topologie |
| Sécurité et destruction automatique | 20% | SSH par clé, isolation réseau prouvée, cron, aucune VM sans échéance |
| Documentation | 15% | README, ADR, DEMO-SCRIPT, rapport technique |
| Travail d'équipe et présentation | 10% | Module développé en solo |

---

*Rapport généré — Juillet 2026*  
*Geneva Institute of Technology × Satom IT & Learning Solutions*
