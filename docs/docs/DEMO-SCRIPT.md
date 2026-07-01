# Scénario de démo live — J3

**Durée cible : 8-10 minutes**  
**URL portail : http://84.234.27.147**

---

## Avant la démo (la veille ou le matin)

1. **Reset de l'environnement** — repartir d'un état propre :
   ```bash
   # Sur la VM plateforme
   ssh -i /tmp/demo_key ubuntu@84.234.27.147
   cd ~/hackathon-platform
   ./scripts/reset_demo.sh
   ```

2. **Répéter le scénario complet** une fois en entier, chronométré.

3. **Enregistrer la répétition réussie** (Xbox Game Bar : `Win+G`) — c'est le Plan B si le live plante.

4. **Vérifier que tout tourne** sur la VM plateforme :
   ```bash
   sudo systemctl status hackathon-portal   # doit être active (running)
   ps aux | grep watch_requests             # watcher actif
   crontab -l                               # cron destroy configuré
   ```

---

## Déroulé

### 1. Contexte (30s)

> "On a construit une plateforme self-service qui gère le cycle de vie complet de VMs cloud pour des étudiants — de la demande jusqu'à la destruction automatique. Tout tourne sur Infomaniak Public Cloud avec de vraies VMs Ubuntu."

Montrer le schéma d'architecture dans `docs/ADR-001-infrastructure.md`.

---

### 2. Architecture (1 min)

Montrer l'ADR à l'écran. Points clés à mentionner :
- OpenTofu + provider OpenStack → Infrastructure as Code réelle
- Un réseau privé par groupe → isolation garantie par topologie
- État déclaratif : même mécanisme pour créer et détruire
- VM plateforme dédiée : le portail tourne en prod 24/7

---

### 3. Démo live (5-6 min)

**Ouvrir http://84.234.27.147 dans le navigateur**

**a. Catalogue et formulaire (1 min)**
- Montrer les 3 templates disponibles (Ubuntu Dev Box, Web Server Sandbox, Data Science Box)
- Tenter de soumettre une demande **sans date de fin** → le formulaire refuse
- Remplir correctement : nom, groupe, template, date de début/fin (mettre une date proche pour montrer le badge), coller la clé publique SSH
- Soumettre → message "en attente de validation"

**b. Validation (30s)**
- Onglet **validation** → la demande apparaît
- Cliquer **approuver**

**c. Provisioning automatique (1-2 min)**
- Sur le terminal de la VM plateforme (`ssh -i /tmp/demo_key ubuntu@84.234.27.147`) :
  ```bash
  tail -f ~/hackathon-platform/logs/watcher.log
  ```
- Montrer le `tofu apply` qui tourne automatiquement
- `Apply complete! Resources: X added` → la VM existe sur Infomaniak

**d. Connexion SSH (30s)**
```bash
ssh -i /tmp/demo_key student@<floating-ip>
whoami   # student
sudo -l  # pas de sudo → sécurité prouvée
exit
```

**e. Isolation réseau (30s)**
```bash
./scripts/test_isolation.sh req-001 req-002 /tmp/demo_key
# OK : vm-req-001 ne peut pas joindre vm-req-002 via IP privée -> isolation confirmée
```

**f. Dashboard et rapport (1 min)**
- Onglet **dashboard** : statut up (point vert), heures actives, coût estimé, badge "expire bientôt"
- Onglet **rapport** : statistiques globales, répartition des coûts par groupe, journal des destructions

**g. Destruction automatique (30s)**
```bash
# Forcer une destruction pour la démo
./scripts/destroy_expired.sh
cat logs/destructions.log
```
Montrer que la VM disparaît du dashboard.

---

### 4. Conclusion (1 min)

> "Les 6 exigences MUST du cahier des charges sont couvertes et prouvées en live. Le tout tourne sur de vraies VMs Infomaniak, pas une simulation. En bonus : dashboard de coûts détaillé et notification visuelle avant échéance."

---

## Plan B — si quelque chose plante

| Problème | Réponse |
|----------|---------|
| Le portail ne charge pas | Montrer `./scripts/status.sh` en terminal — la preuve infra ne dépend pas de l'UI |
| Le watcher ne réagit pas | Lancer `./scripts/provision.sh requests/<id>.json` manuellement — même résultat |
| SSH ne fonctionne pas | Montrer `openstack server show vm-<id>` → statut ACTIVE prouve que la VM existe |
| Tofu plante | Basculer sur la vidéo enregistrée la veille |
| Connexion internet coupée | Tout tourne sur Infomaniak — accès 4G mobile en hotspot |

**Règle d'or :** Ne jamais passer plus de 60 secondes à déboguer devant le jury. Basculer sur le Plan B immédiatement.

---

## Informations techniques pour la démo

```
Portail web          : http://84.234.27.147
VM plateforme (SSH)  : ssh -i /tmp/demo_key ubuntu@84.234.27.147
Clé SSH de test      : /tmp/demo_key (à générer sur la machine de démo)
Projet OpenStack     : PCP-YV8RZH7
Région               : dc3-a
```

---

*Hackathon Juillet 2026 — Geneva Institute of Technology × Satom IT & Learning Solutions*
