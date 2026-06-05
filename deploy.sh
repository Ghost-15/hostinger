#!/bin/bash
# Deploy complet : terraform apply + port-forwards dynamiques + envoi mdp sur ESP32 via IP
# Usage:
#   ./deploy.sh --ip 192.168.1.42
#   ./deploy.sh --ip 192.168.1.42 --esp-port 80
set -e

cd "$(dirname "$0")"

# ── Arguments ─────────────────────────────────────────────────────────────────
ESP32_IP=""
ESP32_HTTP_PORT=80

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)       ESP32_IP="$2";        shift 2 ;;
    --esp-port) ESP32_HTTP_PORT="$2"; shift 2 ;;
    *) echo "Option inconnue : $1"; exit 1 ;;
  esac
done

if [ -z "$ESP32_IP" ]; then
  echo "Erreur : l'IP de l'ESP32 est requise."
  echo "Usage : ./deploy.sh --ip <ip-esp32>"
  echo "L'IP est affichée sur l'écran OLED au démarrage de l'ESP32."
  exit 1
fi

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
echo "=== Envoi du mot de passe sur l'ESP32 ($ESP32_IP) ==="

$PYTHON esp32_send_password.py --ip "$ESP32_IP" --port "$ESP32_HTTP_PORT"

echo ""
echo "=== Déploiement terminé ==="
echo "Le mot de passe est affiché sur l'écran de l'ESP32."
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
