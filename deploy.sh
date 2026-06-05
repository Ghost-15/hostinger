#!/bin/bash
# Deploy complet : terraform apply + port-forwards dynamiques + envoi mdp sur ESP32
# Usage:
#   ./deploy.sh                              # détection automatique du port ESP32
#   ./deploy.sh --port /dev/cu.usbserial-0001
#   ./deploy.sh --port /dev/ttyUSB0 --baud 115200
set -e

cd "$(dirname "$0")"

# ── Arguments ─────────────────────────────────────────────────────────────────
ESP32_PORT=""
BAUD=115200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) ESP32_PORT="$2"; shift 2 ;;
    --baud) BAUD="$2";       shift 2 ;;
    *) echo "Option inconnue : $1"; exit 1 ;;
  esac
done

# ── Python launcher ───────────────────────────────────────────────────────────
get_python() {
  if command -v python3 &>/dev/null; then echo "python3"
  elif command -v python  &>/dev/null; then echo "python"
  else echo ""; fi
}

PYTHON=$(get_python)
if [ -z "$PYTHON" ]; then
  echo "Erreur : aucun interpréteur Python trouvé. Installe Python 3."
  exit 1
fi

# ── Terraform ─────────────────────────────────────────────────────────────────
echo "=== Initialisation Terraform ==="
terraform init -upgrade

echo ""
echo "=== Déploiement des microservices ==="
terraform apply -auto-approve

# ── Port-forwards dynamiques depuis terraform output ──────────────────────────
echo ""
echo "=== Lancement des port-forwards ==="

# Récupère toutes les commandes port-forward depuis les outputs Terraform
# Chaque output retourne un map { "nom" = "kubectl port-forward svc/... X:Y" }
FORWARD_CMDS=()
while IFS= read -r line; do
  [ -n "$line" ] && FORWARD_CMDS+=("$line")
done < <(
  for OUTPUT in wordpress_port_forwards multisite_port_forwards nodejs_port_forwards vps_port_forwards; do
    terraform output -json "$OUTPUT" 2>/dev/null \
      | $PYTHON -c "
import sys, re
data = sys.stdin.read()
for cmd in re.findall(r'\"(kubectl port-forward [^\"]+)\"', data):
    print(cmd)
"
  done
)

if [ ${#FORWARD_CMDS[@]} -eq 0 ]; then
  echo "Aucune commande port-forward trouvée dans les outputs Terraform."
else
  for CMD in "${FORWARD_CMDS[@]}"; do
    # Extrait un label depuis le nom du service (ex: svc/vps-01-svc → vps-01)
    LABEL=$(echo "$CMD" | grep -oE 'svc/[^ ]+' | sed 's/svc\///' | sed 's/-svc//')

    if [[ "$OSTYPE" == "darwin"* ]]; then
      osascript -e "tell application \"Terminal\" to do script \"echo '=== Port-forward : $LABEL ===' && $CMD\""
    else
      if command -v gnome-terminal &>/dev/null; then
        gnome-terminal --tab --title="$LABEL" -- bash -c "echo '=== $LABEL ==='; $CMD; exec bash"
      elif command -v xterm &>/dev/null; then
        xterm -title "$LABEL" -e bash -c "echo '=== $LABEL ==='; $CMD; exec bash" &
      else
        echo "  Lancement en arrière-plan : $CMD"
        $CMD &
      fi
    fi
  done

  echo "${#FORWARD_CMDS[@]} port-forward(s) lancé(s)."
fi

# ── ESP32 ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Envoi du mot de passe SSH sur l'ESP32 ==="

PYTHON_ARGS=("esp32_send_password.py" "--baud" "$BAUD")
if [ -n "$ESP32_PORT" ]; then
  PYTHON_ARGS+=("--port" "$ESP32_PORT")
fi

$PYTHON "${PYTHON_ARGS[@]}"

echo ""
echo "=== Déploiement terminé ==="
echo "Le mot de passe SSH est affiché sur l'écran de l'ESP32."
echo ""
echo "Connexions SSH disponibles :"
terraform output -json vps_port_forwards 2>/dev/null \
  | $PYTHON -c "
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print('  (aucune instance VPS trouvée)')
    sys.exit(0)
data = json.loads(raw)
for name, cmd in data.items():
    port = cmd.split('#')[1].strip() if '#' in cmd else cmd
    print('  ' + name + ' -> ' + port)
" || true
