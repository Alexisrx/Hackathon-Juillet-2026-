"""
Portail self-service — Hackathon Juillet 2026
Couvre les MUST cote Developpeur (catalogue, formulaire, workflow de
validation) et cote Data (dashboard de statut, estimation de couts,
mini-rapport), regroupes dans une seule petite app pour rester simple
a lancer et a demontrer en 3 jours. Peut etre scinde en plusieurs
services plus tard si l'equipe se repartit dessus.

La source de verite reste le dossier requests/ (fichiers JSON), exactement
le meme format que celui consomme par scripts/provision.sh et surveille
par scripts/watch_requests.sh : ce portail n'a donc rien a connaitre de
Terraform/Docker, il ecrit juste des fichiers JSON.
"""
import json
import subprocess
import datetime
from pathlib import Path

from flask import Flask, render_template, request, redirect, url_for, flash

BASE_DIR = Path(__file__).resolve().parent.parent
REQ_DIR = BASE_DIR / "requests"
SCRIPTS_DIR = BASE_DIR / "scripts"
LOG_FILE = BASE_DIR / "logs" / "destructions.log"

REQ_DIR.mkdir(exist_ok=True)
(BASE_DIR / "logs").mkdir(exist_ok=True)

app = Flask(__name__)
app.secret_key = "hackathon-demo-clef-non-secrete"

# Catalogue de templates (MUST: 2-3 templates). Le cout/heure est une
# estimation indicative pour la demo, pas un tarif Infomaniak reel.
CATALOG = {
    "ubuntu-dev": {
        "label": "Ubuntu Dev Box",
        "desc": "Environnement de developpement generaliste (Ubuntu 22.04, outils de base).",
        "cost_per_hour": 0.03,
    },
    "web-sandbox": {
        "label": "Web Server Sandbox",
        "desc": "Bac a sable pour projets web (serveur HTTP, ports exposes).",
        "cost_per_hour": 0.04,
    },
    "data-box": {
        "label": "Data Science Box",
        "desc": "Environnement oriente data/Python pour exercices de cours.",
        "cost_per_hour": 0.06,
    },
}


def load_requests():
    reqs = []
    for f in sorted(REQ_DIR.glob("*.json")):
        try:
            data = json.loads(f.read_text())
            reqs.append(data)
        except (json.JSONDecodeError, OSError):
            continue
    return reqs


def next_id():
    existing_ids = {r.get("id") for r in load_requests()}
    n = 1
    while f"req-{n:03d}" in existing_ids:
        n += 1
    return f"req-{n:03d}"


@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        owner = request.form.get("owner", "").strip()
        group = request.form.get("group", "").strip()
        template = request.form.get("template", "")
        start_date = request.form.get("start_date", "")
        end_date = request.form.get("end_date", "")
        ssh_key = request.form.get("ssh_public_key", "").strip()

        if not end_date:
            flash("La date de fin est obligatoire : aucune VM ne peut etre creee sans echeance.", "error")
            return redirect(url_for("index"))
        if not owner or not group or not ssh_key:
            flash("Tous les champs sont obligatoires.", "error")
            return redirect(url_for("index"))
        if end_date < start_date:
            flash("La date de fin doit etre posterieure a la date de debut.", "error")
            return redirect(url_for("index"))

        vm_id = next_id()
        data = {
            "id": vm_id,
            "owner": owner,
            "group": group,
            "template": template,
            "start_date": start_date,
            "end_date": end_date,
            "ssh_public_key": ssh_key,
            "status": "pending",
        }
        (REQ_DIR / f"{vm_id}.json").write_text(json.dumps(data, indent=2))
        flash(f"Demande {vm_id} envoyee, en attente de validation.", "success")
        return redirect(url_for("index"))

    return render_template(
        "index.html",
        catalog=CATALOG,
        requests=load_requests(),
        today=datetime.date.today().isoformat(),
    )


@app.route("/validate")
def validate():
    pending = [r for r in load_requests() if r.get("status") == "pending"]
    return render_template("pending.html", pending=pending, catalog=CATALOG)


@app.route("/validate/<vm_id>/<action>", methods=["POST"])
def validate_action(vm_id, action):
    f = REQ_DIR / f"{vm_id}.json"
    if not f.exists():
        flash("Demande introuvable.", "error")
        return redirect(url_for("validate"))

    data = json.loads(f.read_text())
    if action == "approve":
        data["status"] = "approved"
        flash(f"{vm_id} approuvee — le provisioning automatique va se declencher.", "success")
    elif action == "refuse":
        data["status"] = "refused"
        flash(f"{vm_id} refusee.", "success")
    else:
        flash("Action inconnue.", "error")
        return redirect(url_for("validate"))

    f.write_text(json.dumps(data, indent=2))
    return redirect(url_for("validate"))


def get_vm_status():
    """Interroge scripts/status.sh (source : etat OpenTofu + OpenStack CLI)
    et enrichit chaque VM avec une estimation simple de cout."""
    try:
        out = subprocess.run(
            [str(SCRIPTS_DIR / "status.sh")],
            capture_output=True, text=True, timeout=30,
        )
        vms = json.loads(out.stdout) if out.stdout.strip() else []
    except (subprocess.SubprocessError, json.JSONDecodeError, FileNotFoundError):
        vms = []

    enriched = []
    for vm in vms:
        server = f"vm-{vm['id']}"
        hours_active = 0.0
        try:
            ts = subprocess.run(
                ["openstack", "server", "show", server, "-f", "value", "-c", "created"],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip()
            created = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
            now = datetime.datetime.now(datetime.timezone.utc)
            hours_active = max((now - created).total_seconds() / 3600, 0)
        except (subprocess.SubprocessError, ValueError):
            pass

        rate = CATALOG.get(vm.get("template"), {}).get("cost_per_hour", 0.03)
        vm["hours_active"] = round(hours_active, 2)
        vm["estimated_cost"] = round(hours_active * rate, 3)

        # Bonus "notification avant echeance" : signale visuellement les VMs
        # proches de leur date de fin, sans systeme d'envoi d'email/SMS.
        try:
            end = datetime.date.fromisoformat(vm["end_date"])
            days_left = (end - datetime.date.today()).days
        except (ValueError, KeyError):
            days_left = None
        vm["days_left"] = days_left
        if days_left is not None and days_left <= 0:
            vm["expiry_flag"] = "expire-today"
        elif days_left is not None and days_left == 1:
            vm["expiry_flag"] = "expire-soon"
        else:
            vm["expiry_flag"] = None

        enriched.append(vm)
    return enriched


@app.route("/dashboard")
def dashboard():
    vms = get_vm_status()
    total_cost = round(sum(v["estimated_cost"] for v in vms), 3)
    return render_template("dashboard.html", vms=vms, total_cost=total_cost)


@app.route("/report")
def report():
    vms = get_vm_status()
    all_reqs = load_requests()
    destroyed_lines = []
    if LOG_FILE.exists():
        destroyed_lines = [
            line for line in LOG_FILE.read_text().splitlines()
            if "destruction VM expiree" in line
        ]

    group_totals = {}
    for vm in vms:
        g = vm.get("group", "?")
        group_totals.setdefault(g, {"count": 0, "cost": 0.0})
        group_totals[g]["count"] += 1
        group_totals[g]["cost"] += vm["estimated_cost"]
    for g in group_totals:
        group_totals[g]["cost"] = round(group_totals[g]["cost"], 3)

    stats = {
        "total_demandes": len(all_reqs),
        "approuvees": len([r for r in all_reqs if r.get("status") in ("approved", "provisioned")]),
        "refusees": len([r for r in all_reqs if r.get("status") == "refused"]),
        "en_attente": len([r for r in all_reqs if r.get("status") == "pending"]),
        "vms_actives": len(vms),
        "vms_detruites": len(destroyed_lines),
        "cout_total_estime": round(sum(v["estimated_cost"] for v in vms), 3),
    }

    return render_template(
        "report.html",
        stats=stats,
        vms=vms,
        destroyed=destroyed_lines,
        group_totals=group_totals,
        generated_at=datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
