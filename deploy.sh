#!/bin/bash
# Deploy complet : terraform apply + envoi mdp SSH sur ESP32
set -e

ESP32_PORT="${1:-}"  # Passer le port en argument: ./deploy.sh /dev/ttyUSB0

echo "=== Initialisation Terraform ==="
terraform init -upgrade

echo ""
echo "=== Déploiement des microservices ==="
terraform apply -auto-approve

echo ""
echo "=== Envoi du mot de passe SSH sur l'ESP32 ==="
if [ -n "$ESP32_PORT" ]; then
    python3 esp32_send_password.py --port "$ESP32_PORT"
else
    python3 esp32_send_password.py
fi

echo ""
echo "=== Déploiement terminé ==="
echo "Le mot de passe SSH est affiché sur l'écran de l'ESP32."
echo "Connexion: ssh admin@localhost -p 2222"
