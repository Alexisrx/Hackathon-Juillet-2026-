# ADR-001 — Infrastructure des VMs (module Système & Réseau)

## Statut
Proposé pour la revue d'architecture du hackathon.

## Contexte
Le cahier des charges demande un provisioning automatisé d'au moins une VM
(réelle ou simulée), avec destruction automatique à échéance, accès SSH
sécurisé et isolation réseau minimale entre groupes — le tout livrable en
3 jours, avec une démo live en fin de hackathon.

## Décisions

### 1. OpenTofu plutôt que Terraform
Fork open-source sous licence MPL, compatible avec l'écosystème Terraform
existant (mêmes providers, même syntaxe HCL). Aucune contrainte de licence
ou de compte pour l'équipe, installation immédiate.

### 2. Provider Docker plutôt qu'un cloud réel pour les "VMs"
Le cahier des charges autorise explicitement une VM "réelle ou simulée".
En 3 jours, le risque principal est une démo qui échoue à cause de
credentials cloud absents, de quotas, ou de virtualisation imbriquée
indisponible sur la machine de démo. Des conteneurs Docker comme VMs :
- s'exécutent sur n'importe quel laptop sans dépendance externe,
- restent pilotés par du vrai code IaC (Terraform/OpenTofu),
- conservent la même architecture que pour un vrai provider cloud — un
  changement de provider (ex. OpenStack/Infomaniak) ne change pas la
  structure du projet, seulement le bloc `provider` et les ressources.

Si un accès cloud réel devient disponible pendant le hackathon, la
migration se limite à remplacer `docker_container`/`docker_network` par
les ressources équivalentes du provider cible.

### 3. Un réseau Docker dédié par groupe = isolation réseau
Chaque groupe d'étudiants reçoit son propre réseau bridge Docker. Deux
conteneurs sur deux réseaux différents ne peuvent pas communiquer par
défaut, ce qui satisfait l'exigence d'isolation sans VLAN ni pare-feu
supplémentaire à configurer en 3 jours. Testable et démontrable en direct
(`scripts/test_isolation.sh`).

### 4. Accès SSH par clé uniquement
Chaque VM reçoit la clé publique de l'étudiant via une variable d'environnement
injectée au démarrage du conteneur. `PasswordAuthentication no` et
`PermitRootLogin no` sont forcés dans `sshd_config`, et les comptes
`root`/`student` sont verrouillés (pas de mot de passe utilisable).

### 5. État désiré déclaratif (`vms.auto.tfvars.json`) pour provisioning ET destruction
Plutôt que d'exécuter des commandes `apply`/`destroy` ciblées au cas par
cas, l'ensemble des VMs qui doivent exister est représenté dans un seul
fichier JSON consommé par Terraform (`var.vms`). Provisionner = ajouter une
entrée puis `tofu apply`. Détruire à échéance = retirer l'entrée expirée
puis `tofu apply` — Tofu détruit automatiquement ce qui n'est plus dans
l'état désiré. Un seul mécanisme de réconciliation pour les deux besoins,
ce qui réduit la surface de bugs en développement intensif.

## Conséquences
- Démo reproductible sans dépendance à un compte cloud externe.
- Migration vers un vrai cloud possible sans réécrire l'architecture.
- La "destruction automatique" repose sur un job périodique
  (`scripts/destroy_expired.sh`, via cron ou systemd timer) plutôt que sur
  un mécanisme natif du cloud — acceptable pour un MVP de hackathon, à
  noter comme limite connue dans le README.
- L'isolation réseau est assurée au niveau Docker, pas au niveau VLAN
  physique — suffisant pour le MUST ("isolation réseau minimale").
