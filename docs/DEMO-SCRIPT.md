# Déroulé de la démo live — J3

Durée cible : 8-10 min. Objectif : prouver que le scénario de bout en bout
fonctionne réellement, pas seulement qu'il est codé.

## Avant la démo (la veille ou le matin même)

1. `./scripts/reset_demo.sh` pour repartir d'un état propre.
2. Répéter le scénario complet une fois en entier, chronométré.
3. **Enregistrer cette répétition réussie** (capture d'écran vidéo,
   ex. l'outil Xbox Game Bar sous Windows `Win+G`, ou OBS) — c'est le Plan B
   si le live plante devant le jury. Mieux vaut montrer un enregistrement
   propre que de perdre 5 minutes à déboguer en direct.
4. Vérifier que Docker Desktop est lancé et que `docker ps` répond avant
   d'arriver devant le jury.

## Déroulé

**1. Contexte (30s)**
Rappel du besoin : plateforme self-service de VMs pour étudiants/formateurs,
cycle de vie complet de la demande à la destruction automatique.

**2. Architecture (1 min)**
Montrer `docs/ADR-001-infrastructure.md` à l'écran : OpenTofu + Docker
(VMs simulées, migration possible vers un cloud réel), un réseau par
groupe pour l'isolation, état déclaratif unique pour provisioning et
destruction.

**3. Démo live (5-6 min)**

```bash
./scripts/demo.sh
```

- Aller sur `http://localhost:5000`, montrer le catalogue de templates.
- Remplir une demande avec une date de fin **dans 2-3 minutes** (pas dans
  10 jours) pour pouvoir montrer la destruction automatique en direct sans
  attendre.
- Montrer qu'une demande **sans date de fin** est refusée par le formulaire
  lui-même (exigence "aucune VM sans échéance", visible dès la saisie).
- Onglet **validation** : approuver la demande.
- Terminal : montrer le watcher qui détecte et provisionne automatiquement
  (`tofu apply` qui tourne tout seul, sans commande manuelle).
- `ssh -i /tmp/demo_key -p <port> student@localhost` pour prouver l'accès
  par clé (pas de mot de passe demandé).
- `./scripts/test_isolation.sh <id_a> <id_b>` avec deux VMs de groupes
  différents pour prouver l'isolation réseau.
- Onglet **dashboard** : statut up/down, coûts estimés, badge "expire
  bientôt".
- Attendre (ou lancer manuellement `./scripts/destroy_expired.sh` dans un
  terminal) pour montrer la VM disparaître automatiquement une fois la
  date de fin atteinte.
- Onglet **rapport** : statistiques globales + répartition des coûts par
  groupe.

**4. Conclusion (1 min)**
Récapituler les 6 exigences MUST couvertes, mentionner les choix
documentés dans l'ADR, et le bonus livré (notification visuelle avant
échéance, dashboard de coûts détaillé).

## Plan B — si quelque chose plante en direct

- Docker/Tofu ne répond pas : couper court, dire "je bascule sur
  l'enregistrement de la répétition" et lancer la vidéo préparée à
  l'avance. Ne pas chercher à déboguer devant le jury.
- Le portail ne charge pas : montrer directement `./scripts/status.sh` et
  `cat logs/destructions.log` dans un terminal — la preuve fonctionnelle
  ne dépend pas de l'UI.
- Le watcher semble ne rien détecter : lancer `./scripts/provision.sh
  requests/<id>.json` manuellement pour ne pas bloquer la démo, et
  mentionner que l'automatisation a été prouvée en répétition.
