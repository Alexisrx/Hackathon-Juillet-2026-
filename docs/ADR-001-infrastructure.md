# ADR-001 — Infrastructure des VMs (module Système & Réseau)

**Statut :** Accepté  
**Date :** Juillet 2026  
**Contexte :** Hackathon 3 jours — Geneva Institute of Technology × Satom IT & Learning Solutions

---

## Contexte

Le cahier des charges demande une plateforme self-service de gestion de VMs pour étudiants et formateurs, avec provisioning automatisé, destruction automatique à échéance, accès SSH sécurisé par clé, et isolation réseau entre groupes. Contrainte principale : livrable en 3 jours avec démo live devant jury.

---

## Décisions

### 1. OpenTofu plutôt que Terraform

**Décision :** Utiliser OpenTofu (fork open-source de Terraform, licence MPL).

**Raisons :** Aucune contrainte de licence ou de compte Terraform Cloud. Compatible 100% avec l'écosystème Terraform (mêmes providers, même syntaxe HCL). Installation immédiate.

---

### 2. Infomaniak Public Cloud (OpenStack) comme provider cible

**Décision :** Utiliser le provider OpenStack v3.4.0 pointant vers `api.pub1.infomaniak.cloud`, région `dc3-a`, projet `PCP-YV8RZH7`.

**Ressources créées par groupe :**
```
openstack_networking_network_v2         réseau privé isolé
openstack_networking_subnet_v2          sous-réseau CIDR unique
openstack_networking_router_v2          router vers ext-floating1
openstack_networking_router_interface_v2
openstack_networking_secgroup_v2        SSH(22) + ICMP autorisés
openstack_networking_secgroup_rule_v2   (x2)
```

**Ressources créées par VM :**
```
openstack_compute_keypair_v2            clé SSH importée
openstack_networking_port_v2            port réseau explicite
openstack_compute_instance_v2           VM Ubuntu 22.04 LTS
openstack_networking_floatingip_v2      IP publique SSH
```

---

### 3. Port réseau explicite pour garantir l'association floating IP

**Décision :** Créer une ressource `openstack_networking_port_v2` explicite par VM et y attacher la floating IP via `port_id`.

**Raisons :** Le provider OpenStack v3 a supprimé `openstack_compute_floatingip_associate_v2`. Sans port explicite, la floating IP est créée avant que le port de la VM soit connu → `port_id: None`, `status: DOWN`. Avec un port explicite, l'ordre est garanti : port → floating IP → VM.

**Dépendance critique ajoutée :**
```hcl
resource "openstack_networking_floatingip_v2" "vm_fip" {
  depends_on = [openstack_networking_router_interface_v2.group_router_iface]
  port_id    = openstack_networking_port_v2.vm_port[each.key].id
}
```

Sans `depends_on`, OpenStack retourne `ExternalGatewayForFloatingIPNotFound` car le subnet n'est pas encore routé vers l'externe au moment de la création de la floating IP.

---

### 4. CIDRs uniques par groupe (192.168.X0.0/24)

**Décision :** Attribuer un CIDR unique à chaque groupe, dérivé de son index alphabétique parmi les groupes actifs.

**Raisons :** Avec tous les groupes sur `10.10.0.0/24`, un bastion connecté à plusieurs réseaux ne pourrait pas router sans ambiguïté — le système d'exploitation verrait plusieurs interfaces avec la même plage d'IP et ne saurait pas par laquelle joindre `10.10.0.128`. Des CIDRs distincts rendent le routage déterministe.

**Implémentation Terraform :**
```hcl
locals {
  groups_list = sort(tolist(toset([for k, v in var.vms : v.group])))
  group_cidrs = {
    for idx, g in local.groups_list :
    g => "192.168.${(idx + 1) * 10}.0/24"
  }
}
```

**Résultat pour les groupes actuels :**
```
groupe-b (idx=0) → 192.168.10.0/24
groupe-c (idx=1) → 192.168.20.0/24
groupe-d (idx=2) → 192.168.30.0/24
...
```

**Comportement à l'ajout d'un groupe :** Les CIDRs existants ne changent pas — le nouveau groupe reçoit le CIDR suivant. ✅

**Comportement à la suppression d'un groupe :** Les groupes suivants changent d'index → CIDR shift → OpenTofu veut recréer les subnets. ⚠️ Acceptable pour un hackathon ; en production, définir les CIDRs explicitement dans `variables.tf`.

---

### 5. Isolation réseau par topologie OpenStack

**Décision :** Un réseau privé + router dédiés par groupe d'étudiants, avec un CIDR unique.

**Raisons :** Deux VMs sur deux réseaux OpenStack différents avec des CIDRs distincts ne peuvent pas se joindre par IP privée sans route explicite entre eux. L'isolation est au niveau infrastructure, testable et démontrable en live avec `test_isolation.sh`.

**Preuve :**
```
vm-req-001 (192.168.10.x, groupe-b) → ping 192.168.20.x (groupe-c)
→ Destination Host Unreachable (pas de route)
→ Isolation confirmée
```

**Limite :** Les floating IPs sont routées par internet — deux VMs de groupes différents peuvent se joindre via leurs IPs publiques. L'isolation est au niveau réseau privé interne, ce qui répond à "isolation réseau minimale entre groupes".

---

### 6. Accès SSH par clé uniquement, utilisateur `student` sans sudo

**Décision :** Injection via cloud-init, durcissement sshd via `/etc/ssh/sshd_config.d/99-hardening.conf`.

```yaml
#cloud-config
users:
  - name: student
    ssh_authorized_keys:
      - <clé publique de l'étudiant>
    shell: /bin/bash
write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
runcmd:
  - systemctl restart ssh
```

---

### 7. État déclaratif unique (`vms.auto.tfvars.json`)

**Décision :** L'ensemble des VMs qui doivent exister est dans un seul fichier JSON.

- **Provisionner** = ajouter une entrée + `tofu apply`
- **Détruire** = retirer l'entrée + `tofu apply` (OpenTofu détruit automatiquement)

Un seul mécanisme de réconciliation pour les deux besoins.

---

### 8. VM plateforme dédiée sur Infomaniak

**Décision :** Portail Flask + watcher + OpenTofu sur une VM Infomaniak dédiée (`84.234.27.147`), exposée via nginx sur le port 80.

**Note :** La VM plateforme est sur le réseau `hackathon-groupe-a` (géré manuellement, hors IaC) pour éviter un conflit lors des resets — les ressources `groupe-a` ont été retirées du state Tofu avec `tofu state rm` pour préserver la connectivité de la VM plateforme.

```
nginx :80 → Flask :5000
systemd hackathon-portal (restart=always)
watch_requests.sh (nohup)
destroy_expired.sh (cron */10 * * * *)
```

---

### 9. État Terraform local (limite MVP)

**Décision :** `terraform.tfstate` stocké sur la VM plateforme.

**Limite :** Point de défaillance unique. En production, utiliser un backend distant (OpenStack Swift, Terraform Cloud).

---

## Résumé des choix

| Décision | Alternative écartée | Raison du choix |
|----------|---------------------|-----------------|
| OpenTofu | Terraform commercial | Licence libre, zéro friction |
| Infomaniak OpenStack | AWS/Azure | Mentionné dans le cahier des charges |
| Port réseau explicite | Floating IP implicite | Provider v3 incompatible avec l'approche implicite |
| CIDRs uniques 192.168.X0.0/24 | CIDR unique 10.10.0.0/24 | Routage sans ambiguïté pour futur bastion |
| Réseau privé par groupe | Security groups seuls | Isolation par topologie, plus robuste |
| cloud-init | Ansible | Natif OpenStack, zéro dépendance externe |
| VM plateforme dédiée | Laptop de développement | Portail accessible depuis internet 24/7 |
| État local | Backend distant | Compromis MVP 3 jours |

---

*Geneva Institute of Technology × Satom IT & Learning Solutions — Hackathon Juillet 2026*
