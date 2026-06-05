# Local Hosting — Terraform + Kubernetes (kind)

Provider local simulant un hébergeur avec 4 machines.

## Architecture

```
kind cluster (hosting-local)
├── Machine 1 → WordPress Multisite  (réseau de sites WP) → :8080
├── Machine 2 → WordPress            (site unique + MySQL) → :8081
│              MySQL                 (base partagée)       → :3306
├── Machine 3 → Node.js              (API serveur)         → :8082
└── Machine 4 → Debian VPS           (SSH accessible)      → :2222
```

Un mot de passe unique est généré aléatoirement à chaque `terraform apply` et partagé par tous les services. Il est automatiquement envoyé et affiché sur un écran OLED connecté à un ESP32.

---

## Prérequis

### Windows

```powershell
winget install Kubernetes.kind
winget install Kubernetes.kubectl
winget install Hashicorp.Terraform
pip install pyserial
```

Docker Desktop est requis : https://www.docker.com/products/docker-desktop

### macOS

```bash
brew install kind kubectl terraform
pip3 install pyserial
```

Docker Desktop est requis : https://www.docker.com/products/docker-desktop

### Linux (Debian/Ubuntu)

```bash
# kind
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# pyserial
pip3 install pyserial

# Docker Engine
sudo apt install -y docker.io
sudo usermod -aG docker $USER  # puis se reconnecter
```

---

## Déploiement complet

### Étape 1 — Créer le cluster kind

```bash
kind create cluster --name hosting-local --image kindest/node:v1.34.0
kubectl cluster-info --context kind-hosting-local
kubectl get nodes
```

### Étape 2 — Déployer avec Terraform + envoyer le mdp sur l'ESP32

Trouver d'abord le port série de l'ESP32 :

| OS      | Commande                          | Exemple de port              |
|---------|-----------------------------------|------------------------------|
| Windows | `Get-PnpDevice -Class Ports`      | `COM4`                       |
| macOS   | `ls /dev/cu.usb*`                 | `/dev/cu.usbserial-0001`     |
| Linux   | `ls /dev/ttyUSB* /dev/ttyACM*`    | `/dev/ttyUSB0`               |

> **Linux uniquement** — accès au port série sans sudo :
> ```bash
> sudo usermod -aG dialout $USER  # puis se reconnecter
> ```

**Déploiement en une commande :**

```bash
# macOS / Linux
./deploy.sh /dev/ttyUSB0               # Linux
./deploy.sh /dev/cu.usbserial-0001     # macOS
./deploy.sh                            # détection automatique
```

```powershell
# Windows
.\deploy.ps1 -Port COM4
```

Si tu ne passes pas `-Port`, le script PowerShell envoie quand même le mot de passe à l'ESP32 en s'appuyant sur la détection automatique du script Python.

**Ou manuellement :**

```bash
terraform init
terraform apply

# macOS / Linux
python3 esp32_send_password.py --port /dev/ttyUSB0

# Windows
python esp32_send_password.py --port COM4
```

Remplace `COM4` par le vrai port de l'ESP32. Si le port indiqué n'existe pas, le script prend automatiquement un port série disponible.

Le mot de passe généré s'affiche automatiquement sur l'écran de l'ESP32 dès que le déploiement est terminé.

### Étape 3 — Lancer les port-forwards

Dans 4 terminaux séparés :

```bash
kubectl port-forward svc/multisite-svc   8080:80     # WP Multisite
kubectl port-forward svc/wordpress-svc   8081:80     # WP classique
kubectl port-forward svc/nodejs-svc      8082:3000   # Node.js
kubectl port-forward svc/debian-vps-svc  2222:2222   # SSH
```

---

## Accès aux services

| Service             | URL / Commande                  | User      |
|---------------------|---------------------------------|-----------|
| WordPress Multisite | http://localhost:8080           | wp_user   |
| WordPress classique | http://localhost:8081           | wp_user   |
| Node.js API         | http://localhost:8082           | —         |
| Debian VPS SSH      | `ssh admin@localhost -p 2222`   | admin     |
| MySQL               | localhost:3306                  | wp_user   |

Le mot de passe est affiché sur l'écran OLED de l'ESP32. Il change à chaque `terraform apply`.

Pour l'afficher aussi dans le terminal :

```bash
terraform output shared_password
```

---

## ESP32 — Affichage du mot de passe

Un ESP32 avec un écran OLED SSD1306 (128x64) affiche le mot de passe en temps réel après chaque déploiement.

### Câblage

| OLED SSD1306 | ESP32  |
|--------------|--------|
| SDA          | GPIO 8 |
| SCL          | GPIO 3 |
| VCC          | 3.3V   |
| GND          | GND    |

### Sketch Arduino

Charger [`esp32_display/esp32_display.ino`](esp32_display/esp32_display.ino) via Arduino IDE.

Librairies requises (Gestionnaire de bibliothèques) :
- `Adafruit SSD1306`
- `Adafruit GFX Library`

### Comportement de l'écran

L'écran affiche en permanence le mot de passe en haut, puis fait défiler les 5 services toutes les 3 secondes :

```
MDP: aB3!xZ9k#mQpLf
──────────────────
WP Multisite
user: wp_user
port: :8080
1/5 [████░░░░░░]
```

---

## Configurer WordPress Multisite

1. Aller sur **http://localhost:8080/wp-admin**
2. Installer WordPress (user : `wp_user`, mdp : voir écran ESP32)
3. Aller dans **Outils > Configuration du réseau**
4. Choisir **"Sous-répertoires"** (mode subdirectory)
5. Cliquer **Installer**

Exemples de sites du réseau :
- `http://localhost:8080/` → site principal
- `http://localhost:8080/blog1/` → sous-site 1
- `http://localhost:8080/shop/` → sous-site 2

---

## Commandes utiles

```bash
kubectl get pods
kubectl get services
kubectl logs deployment/wp-multisite
kubectl logs deployment/wordpress
kubectl logs deployment/mysql
kubectl logs deployment/nodejs-server
kubectl exec -it deployment/debian-vps -- bash
```

---

## Tout supprimer

```bash
terraform destroy
kind delete cluster --name hosting-local
```
