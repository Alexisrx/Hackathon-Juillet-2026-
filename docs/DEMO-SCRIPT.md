# Scénario de démo live — J3

**Durée cible : 8-10 minutes**  
**URL portail : http://84.234.27.147**  
**VM plateforme : ssh -i /tmp/demo_key ubuntu@84.234.27.147**

---

## Avant la démo (la veille ou le matin)

1. **Reset et vérification** sur la VM plateforme :
   ```bash
   ssh -i /tmp/demo_key ubuntu@84.234.27.147
   cd ~/hackathon-platform
   sudo systemctl status hackathon-portal    # doit être active (running)
   ps aux | grep watch_requests              # watcher actif
   crontab -l                                # cron */10 * * * *
   ./scripts/reset_demo.sh                   # repartir propre
   ```

2. **Répéter le scénario complet** une fois, chronométré.

3. **Enregistrer la répétition** (Xbox Game Bar `Win+G` ou OBS) — Plan B si le live plante.

4. **Générer les clés SSH de test** sur la machine de démo :
   ```bash
   ssh-keygen -t ed25519 -f /tmp/demo_key_alice -N ""
   ssh-keygen -t ed25519 -f /tmp/demo_key_bob -N ""
   cat /tmp/demo_key_alice.pub  # à copier dans le formulaire
   ```

---

## Déroulé

### 1. Contexte (30s)

> "On a construit une plateforme self-service complète de gestion de VMs cloud. Un étudiant fait une demande, un formateur valide, la VM est provisionnée automatiquement sur Infomaniak Public Cloud et détruite à son échéance. Tout est en Infrastructure as Code avec OpenTofu."

---

### 2. Architecture (1 min)

Montrer `docs/ADR-001-infrastructure.md`. Points clés :
- OpenTofu + provider OpenStack → vraies VMs Infomaniak
- **CIDRs uniques par groupe** : groupe-b → `192.168.10.0/24`, groupe-c → `192.168.20.0/24` — pas de route entre groupes, isolation par topologie réseau
- État déclaratif : même mécanisme pour créer et détruire
- VM plateforme dédiée : portail accessible depuis internet 24/7

---

### 3. Démo live (5-6 min)

**Ouvrir http://84.234.27.147**

**a. Catalogue et refus sans date de fin (30s)**
- Montrer les 3 templates disponibles
- Tenter de soumettre sans date de fin → refus immédiat du formulaire
- C'est voulu : "aucune VM sans échéance"

**b. Demande complète (30s)**
- Remplir : nom=alice, groupe=groupe-b, date de fin proche, coller `/tmp/demo_key_alice.pub`
- Soumettre → "en attente de validation"

**c. Validation (15s)**
- Onglet **validation** → approuver
- Statut passe à "approved"

**d. Provisioning automatique (1-2 min)**
- Dans le terminal de la VM plateforme :
  ```bash
  tail -f ~/hackathon-platform/logs/watcher.log
  ```
- Montrer `tofu apply` qui tourne tout seul, sans commande manuelle
- `Apply complete! Resources: 11 added` → VM ACTIVE sur Infomaniak avec IP `192.168.10.x`

**e. Connexion SSH sécurisée (30s)**
```bash
ssh -i /tmp/demo_key_alice student@<floating-ip>
whoami      # student
sudo -l     # pas de sudo → sécurité prouvée
exit
```

**f. Isolation réseau avec CIDRs distincts (45s)**

Créer une deuxième VM dans groupe-c (`192.168.20.0/24`) :
```bash
./scripts/new_request.sh req-002 bob groupe-c 2026-07-10 /tmp/demo_key_bob.pub
./scripts/provision.sh requests/req-002.json
```

Puis prouver l'isolation :
```bash
./scripts/test_isolation.sh req-001 req-002 /tmp/demo_key_alice
# OK : vm-req-001 (192.168.10.x) ne peut pas joindre vm-req-002 (192.168.20.x)
# → CIDRs différents, pas de route entre les réseaux
```

**g. Dashboard et rapport (1 min)**
- Onglet **dashboard** : statut up (point vert), heures actives, coût estimé, badge "expire bientôt"
- Onglet **rapport** : stats globales, répartition coûts par groupe, journal destructions

**h. Destruction automatique (30s)**
```bash
./scripts/destroy_expired.sh
cat logs/destructions.log
```
La VM expirée disparaît du dashboard — toutes ses ressources (instance, port, floating IP, keypair) sont supprimées.

---

### 4. Conclusion (1 min)

> "6 exigences MUST couvertes, sur de vraies VMs Infomaniak. En bonus : dashboard de coûts détaillé et notification avant échéance. Le tout est reproductible depuis zéro avec `git clone` + `tofu apply`."

---

## Plan B — si quelque chose plante

| Problème | Réponse |
|----------|---------|
| Portail inaccessible | `ssh ubuntu@84.234.27.147 "sudo systemctl restart hackathon-portal"` |
| Watcher ne réagit pas | `./scripts/provision.sh requests/<id>.json` manuellement |
| SSH vers VM refuse | Attendre 60s (cloud-init), puis `openstack server show vm-<id>` |
| Tofu plante | Basculer sur la vidéo enregistrée la veille |
| Connexion internet coupée | Hotspot 4G mobile |
| Plus de 60s de débogage | Basculer sur la vidéo — ne jamais déboguer plus d'1 minute devant le jury |

---

## Informations techniques

```
Portail web              http://84.234.27.147
VM plateforme (SSH)      ssh -i /tmp/demo_key ubuntu@84.234.27.147
Projet OpenStack         PCP-YV8RZH7
Région                   dc3-a
Image                    Ubuntu 22.04 LTS (bdee52cf-...)
Flavor                   a1-ram2-disk50-perf1 (1 vCPU, 2 GB, 50 GB)
Réseau ext (floating IP) ext-floating1

CIDRs par groupe (alphabétique) :
  groupe-b → 192.168.10.0/24  (actuellement actif)
  groupe-c → 192.168.20.0/24
  groupe-d → 192.168.30.0/24
  ...
```

---

*Hackathon Juillet 2026 — Geneva Institute of Technology × Satom IT & Learning Solutions*
