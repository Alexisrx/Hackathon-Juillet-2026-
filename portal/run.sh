#!/usr/bin/env bash
# run.sh — lance le portail web. Cree un venv local si besoin.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q -r requirements.txt

echo "Portail disponible sur http://localhost:5000"
python3 app.py
