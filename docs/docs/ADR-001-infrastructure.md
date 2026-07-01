# ADR-001 — Infrastructure des VMs (module Système & Réseau)

**Statut :** Accepté  
**Date :** Juillet 2026  
**Contexte :** Hackathon 3 jours — Geneva Institute of Technology × Satom IT & Learning Solutions

---

## Contexte

Le cahier des charges demande une plateforme self-service de gestion de VMs pour étudiants et formateurs, avec :
- Provisioning automatisé à la demande
- Destruction automatique à échéance (aucune VM sans date de fin)
- Accès SSH sécurisé par clé
- Isolation réseau entre groupes
- Dashboard de suivi

Contrainte principale : livrable en 3 jours avec démo live devant jury.

---

## Décisions

### 1. OpenTofu plutôt que Terraform

**Décision :** Utiliser OpenTofu (fork open-source de Terraform, licence MPL).

**Raisons :**
- Aucune contrainte de licence ou de compte Terraform Cloud
- Compatible à 100% avec l'écosystème Terraform (mêmes providers, même syntaxe HCL)
- Installation immédiate via script officiel

**Conséquences :** Zéro friction pour l'équipe, migration vers Terraform commerciale possible sans réécriture.

---

### 2. Infomaniak Public Cloud (OpenStack) comme provider cible

**Décision :** Utiliser le provider OpenStack (`terraform-provider-openstack/openstack ~> 3.0`) pointant vers `api.pub1.infomaniak.cloud`.

**Raisons :**
- Infomaniak est le cloud mentionné explicitement dans le cahier des charges du hackathon de juin
- Provider OpenStack mature et bien documenté
- Hébergeur suisse, données en Suisse (pertinent pour le GIT)

**Ressources créées par groupe :**
```
openstack_networking_network_v2     → réseau privé isolé
openstack_networking_subnet_v2      → sous-réseau 10.10.0.0/24
openstack_networking_router_v2      → router vers internet (ext-floating1)
openstack_networking_router_interface_v2
openstack_networking_secgroup_v2    → SSH (22) + ICMP autorisés, reste bloqué
openstack_networking_secgroup_rule_v2 (x2)
```

**Ressources créées par VM :**
```
openstack_compute_keypair_v2        → clé SSH importée
openstack_networking_port_v2        → port réseau explicite (requis pour floating IP)
openstack_compute_instance_v2       → VM Ubuntu 22.04, flavor a1-ram2-disk50-perf1
openstack_networking_floatingip_v2  → IP publique pour accès SSH
```

---

### 3. Port réseau explicite pour garantir l'association floating IP

**Décision :** Créer une ressource `openstack_networking_port_v2` explicite par VM et y attacher directement la floating IP via `port_id`.

**Raisons :**
- Le provider OpenStack v3 a supprimé `openstack_compute_floatingip_associate_v2`
- Sans port explicite, la floating IP est créée avant que le port de la VM soit connu → association impossible
- Avec un port explicite, l'ordre de création est garanti : port → floating IP → VM

**Dépendance ajoutée :**
```hcl
resource "openstack_networking_floatingip_v2" "vm_fip" {
  depends_on = [openstack_networking_router_interface_v2.group_router_iface]
  port_id    = openstack_networking_port_v2.vm_port[each.key].id
}
```

---

### 4. Isolation réseau par topologie OpenStack

**Décision :** Un réseau privé + router dédiés par groupe d'étudiants.

**Raisons :**
- Deux VMs sur deux réseaux OpenStack différents ne peuvent pas se joindre par IP privée sans route explicite entre eux
- L'isolation est au niveau infrastructure, pas logicielle — plus robuste et démontrable
- Testable en direct : `scripts/test_isolation.sh` SSH dans VM_A et tente de pinguer l'IP privée de VM_B → doit échouer

**Limites :** Les floating IPs sont publiques — deux VMs de groupes différents peuvent se joindre via leurs IPs publiques (internet). L'isolation est au niveau du réseau privé interne, ce qui est l'exigence du cahier des charges ("isolation réseau minimale").

---

### 5. Accès SSH par clé uniquement, utilisateur `student` sans sudo

**Décision :** Injection de la clé SSH via cloud-init, durcissement sshd via `/etc/ssh/sshd_config.d/99-hardening.conf`.

**Configuration cloud-init :**
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

**Conséquences :** Chaque VM reçoit la clé publique de l'étudiant spécifiée dans sa demande. Connexion : `ssh student@<floating-ip>`.

---

### 6. État déclaratif unique (`vms.auto.tfvars.json`) pour provisioning ET destruction

**Décision :** L'ensemble des VMs qui doivent exister est représenté dans un seul fichier JSON consommé par Terraform via `var.vms`.

**Principe :**
- Provisionner = ajouter une entrée dans `vms` puis `tofu apply`
- Détruire = retirer l'entrée expirée puis `tofu apply`
- Tofu détruit automatiquement ce qui n'est plus dans l'état désiré

**Conséquences :** Un seul mécanisme de réconciliation pour les deux besoins, surface de bugs réduite.

---

### 7. VM plateforme dédiée sur Infomaniak

**Décision :** Déployer le portail Flask + watcher + OpenTofu sur une VM Infomaniak dédiée (`vm-platform`, IP : `84.234.27.147`), exposée via nginx sur le port 80.

**Raisons :**
- Portail accessible depuis internet pour le jury et les étudiants
- Watcher tourne en permanence sans dépendre du laptop de développement
- Architecture réaliste : séparation entre la plateforme de gestion et les VMs gérées

**Stack de la VM plateforme :**
```
nginx :80 → proxy → Flask :5000
systemd service hackathon-portal (restart=always)
watch_requests.sh (nohup, arrière-plan)
destroy_expired.sh (cron */10 * * * *)
```

---

### 8. État Terraform stocké localement (limite MVP)

**Décision :** `terraform.tfstate` stocké sur la VM plateforme (filesystem local).

**Raisons :** En 3 jours, configurer un backend distant (OpenStack Swift, S3, Terraform Cloud) aurait consommé du temps de développement critique.

**Limite connue :** Si la VM plateforme est perdue, l'état Terraform est perdu et les ressources OpenStack deviennent "orphelines" (toujours facturées, mais non gérées par Tofu). En production, utiliser un backend distant.

---

## Résumé des choix justifiés

| Décision | Alternative écartée | Raison du choix |
|----------|---------------------|-----------------|
| OpenTofu | Terraform commercial | Licence libre, zéro friction |
| Infomaniak OpenStack | AWS/Azure/GCP | Mentionné dans le cahier des charges, hébergeur suisse |
| Port réseau explicite | Floating IP implicite | Provider v3 ne supporte plus l'association implicite |
| Réseau privé par groupe | Security groups seuls | Isolation garantie par topologie, pas par règles |
| cloud-init pour SSH | Ansible | Plus simple, natif OpenStack, zéro dépendance externe |
| VM plateforme dédiée | Laptop de développement | Portail accessible depuis internet 24/7 |
| État local | Backend distant | Compromis MVP 3 jours |

---

*Geneva Institute of Technology × Satom IT & Learning Solutions — Hackathon Juillet 2026*
