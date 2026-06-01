# 🏠 Local Hosting — Terraform + Kubernetes (kind)

Provider local simulant un hébergeur avec 4 machines.

## 📦 Architecture

```
kind cluster (hosting-local)
├── Machine 1 → WordPress Multisite  (réseau de sites WP) → :8080
├── Machine 2 → WordPress            (site unique + MySQL) → :8081
│              MySQL                 (base partagée)
├── Machine 3 → Node.js              (API serveur)        → :8082
└── Machine 4 → Debian VPS           (SSH accessible)     → :2222
```

---

## 🛠️ Prérequis

```powershell
# Docker Desktop (requis pour kind)
# Télécharger : https://www.docker.com/products/docker-desktop

winget install Kubernetes.kind
winget install Kubernetes.kubectl
terraform --version  # déjà installé
```

---

## 🚀 Déploiement complet

### Étape 1 — Créer le cluster kind

```powershell
kind create cluster --name hosting-local --image kindest/node:v1.34.0
kubectl config current-context

Vérifier l'état du cluster :
kubectl cluster-info --context kind-hosting-local
kubectl get nodes

Vérifier les pods système :
kubectl get pods -A

# → kind-hosting-local
```

### Étape 2 — Déployer avec Terraform

```powershell
cd terraform-local-hosting
terraform init
terraform apply
# Taper "yes"
```

### Étape 3 — Lancer les port-forwards

```powershell
.\port-forward.ps1 ou Get-Content .\port-forward.ps1
```

Ou manuellement dans 4 terminaux :

```powershell
kubectl port-forward svc/multisite-svc   8080:80    # WP Multisite
kubectl port-forward svc/wordpress-svc   8081:80    # WP classique
kubectl port-forward svc/nodejs-svc      8082:3000  # Node.js
kubectl port-forward svc/debian-vps-svc  2222:22    # SSH
```

---

## 🌐 Accès aux services

| Service              | URL / Commande                       |
|----------------------|--------------------------------------|
| WordPress Multisite  | http://localhost:8080                |
| WordPress classique  | http://localhost:8081                |
| Node.js API          | http://localhost:8082                |
| Debian VPS SSH       | `ssh root@localhost -p 2222`         |

Mot de passe SSH : `debian_root_pass`

---

## 🌐 Configurer WordPress Multisite

Le Multisite WordPress est activé via `wp-config.php` automatiquement.
Après le premier démarrage :

1. Aller sur **http://localhost:8080/wp-admin**
2. Installer WordPress normalement (admin/mot de passe)
3. Aller dans **Outils > Configuration du réseau**
4. Choisir **"Sous-répertoires"** (mode subdirectory)
5. Cliquer **Installer**
6. WordPress affiche 2 blocs de code à coller dans `wp-config.php` et `.htaccess`

Ajouter des sous-sites via :
**Mes Sites > Administration réseau > Sites > Ajouter**

Exemples de sites du réseau :
- `http://localhost:8080/` → site principal
- `http://localhost:8080/blog1/` → sous-site 1
- `http://localhost:8080/shop/` → sous-site 2

---

## ⚙️ WordPress + MySQL

Les deux WordPress (Multisite + classique) utilisent MySQL. Les bases `wordpress_db` et `wordpress_multisite_db` sont créées automatiquement au premier démarrage du serveur MySQL.

Après le premier démarrage d'un pod WordPress :

```powershell
# Multisite
kubectl exec -it deployment/wp-multisite -- bash

# Classique
kubectl exec -it deployment/wordpress -- bash
```

---

## 🔍 Commandes utiles

```powershell
kubectl get pods
kubectl get services
kubectl logs deployment/wp-multisite
kubectl logs deployment/wordpress
kubectl logs deployment/mysql
kubectl exec -it deployment/debian-vps -- bash
```

---

## 🧹 Tout supprimer

```powershell
terraform destroy
kind delete cluster --name hosting-local
```
