/qu#!/bin/bash
# port-forward.sh
# Detecte tous les services du cluster et lance les port-forwards automatiquement

NAMESPACE="${1:-default}"
START_PORT=8080

echo "Namespace : $NAMESPACE"
echo "Recuperation des services..."

# Stoppe les port-forwards existants
EXISTING=$(pgrep -f 'kubectl port-forward' 2>/dev/null)
if [ -n "$EXISTING" ]; then
  echo "Arret des port-forwards existants..."
  kill $EXISTING 2>/dev/null
  sleep 1
fi

# Recupère les services avec leurs ports (nom:port), exclut ceux sans selector
TMPFILE=$(mktemp)
kubectl get svc -n "$NAMESPACE" --no-headers \
  -o custom-columns="NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector" 2>/dev/null \
  | awk '$3 != "<none>" {print $1 ":" $2}' > "$TMPFILE"

SERVICES=()
while IFS= read -r line; do
  SERVICES+=("$line")
done < "$TMPFILE"
rm -f "$TMPFILE"

if [ ${#SERVICES[@]} -eq 0 ]; then
  echo "Aucun service trouve dans le namespace '$NAMESPACE'."
  exit 1
fi

echo ""
echo "Demarrage des port-forwards..."

LOCAL_PORT=$START_PORT
declare -a SUMMARIES

for entry in "${SERVICES[@]}"; do
  SVC_NAME="${entry%%:*}"
  SVC_PORT="${entry##*:}"

  kubectl port-forward "svc/$SVC_NAME" "${LOCAL_PORT}:${SVC_PORT}" -n "$NAMESPACE" &
  PID=$!
  echo "  $SVC_NAME : localhost:${LOCAL_PORT} -> ${SVC_PORT}  (pid $PID)"
  SUMMARIES+=("  $SVC_NAME : http://localhost:${LOCAL_PORT}")
  LOCAL_PORT=$((LOCAL_PORT + 1))
done

echo ""
echo "Services disponibles :"
for s in "${SUMMARIES[@]}"; do
  echo "$s"
done
echo ""
echo "Pour stopper : kill \$(pgrep -f 'kubectl port-forward')"
echo ""

wait
