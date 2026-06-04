# Local Hosting — Terraform + Kubernetes (kind)

Provider local simulant un hébergeur avec des instances dynamiques créées/supprimées à la volée via `for_each`.

## Architecture

```
kind cluster (hosting-local)
├── MySQL               (instance unique partagée)
├── WordPress Multisite (N instances) → for_each sur multisite_instances
├── WordPress           (N instances) → for_each sur wordpress_instances
├── Node.js             (N instances) → for_each sur nodejs_instances
└── VPS Debian SSH      (N instances) → for_each sur vps_instances
```

---

## Prérequis

```powershell
winget install Kubernetes.kind
winget install Kubernetes.kubectl
terraform --version
```

---

## Déploiement

### 1 — Créer le cluster kind

```powershell
kind create cluster --name hosting-local --image kindest/node:v1.34.0
kubectl cluster-info --context kind-hosting-local
kubectl get nodes
```

### 2 — Préparer le fichier de configuration

```powershell
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars avec vos valeurs
```

### 3 — Déployer avec Terraform

```powershell
terraform init
terraform apply
```

### 4 — Lancer les port-forwards

**Windows (PowerShell) :**

```powershell
.\port-forward.ps1
```

**macOS / Linux :**

```bash
bash port-forward.sh
```

Le script `port-forward.sh` détecte automatiquement tous les services du cluster et assigne les ports à partir de 8080.

Ou manuellement par service :

```bash
kubectl port-forward svc/multisite-01-svc 8080:80
kubectl port-forward svc/wordpress-01-svc 8081:80
kubectl port-forward svc/nodejs-01-svc 8082:3000
kubectl port-forward svc/vps-01-svc 2222:22
kubectl port-forward svc/vps-02-svc 2223:22
```

---

## Créer et supprimer des instances à la volée

Toutes les instances sont pilotées par des maps dans `variables.tf` (ou un fichier `.tfvars`).  
**Ajouter** une entrée → `terraform apply` crée l'instance.  
**Supprimer** une entrée → `terraform apply` détruit l'instance.

### Configuration actuelle déployée

```hcl
# terraform.tfvars
wordpress_instances = {
  "wordpress-01" = { db_name = "wp_db_01", db_user = "wp_user_01", db_pass = "wp_pass_01", port = 8081 }
}

multisite_instances = {
  "multisite-01" = { db_name = "wp_multisite_01", db_user = "ms_user_01", db_pass = "ms_pass_01", port = 8080 }
}

nodejs_instances = {
  "nodejs-01" = { port = 8082 }
}

vps_instances = {
  "vps-01" = { password = "debian_root_pass", ssh_port = 2222 }
  "vps-02" = { password = "debian_root_pass", ssh_port = 2223 }
}
```

### Exemple — ajouter un WordPress

```hcl
# terraform.tfvars
wordpress_instances = {
  "wordpress-01" = { db_name = "wp_db_01", db_user = "wp_user_01", db_pass = "wp_pass_01", port = 8081 }
  "wordpress-02" = { db_name = "wp_db_02", db_user = "wp_user_02", db_pass = "wp_pass_02", port = 8083 }
}
```

### Exemple — ajouter un VPS

```hcl
# terraform.tfvars
vps_instances = {
  "vps-01" = { password = "debian_root_pass", ssh_port = 2222 }
  "vps-02" = { password = "debian_root_pass", ssh_port = 2223 }
  "vps-03" = { password = "pass3", ssh_port = 2224 }
}
```

### Exemple — supprimer une instance

Retirez l'entrée du map dans `variables.tf` ou `terraform.tfvars`, puis :

```powershell
terraform apply
```

Terraform détruira uniquement les ressources associées à cette clé (deployment, service, PVC).

---

## Variables disponibles

| Variable              | Type             | Description                              |
|-----------------------|------------------|------------------------------------------|
| `wordpress_instances` | `map(object)`    | Instances WordPress (site unique)        |
| `multisite_instances` | `map(object)`    | Instances WordPress Multisite            |
| `nodejs_instances`    | `map(object)`    | Instances Node.js                        |
| `vps_instances`       | `map(object)`    | Instances VPS Debian SSH                 |
| `mysql_root_password` | `string`         | Mot de passe root MySQL                  |

Chaque objet `wordpress_instances` / `multisite_instances` :

```hcl
{
  db_name = string  # nom de la base de données
  db_user = string  # utilisateur MySQL
  db_pass = string  # mot de passe MySQL
  port    = number  # port local pour le port-forward
}
```

Chaque objet `vps_instances` :

```hcl
{
  password = string  # mot de passe SSH admin
  ssh_port = number  # port local pour le port-forward SSH
}
```

---

## Accès aux services

Après `kubectl port-forward`, les accès avec la configuration actuelle :

| Instance          | URL / Commande                              |
|-------------------|---------------------------------------------|
| multisite-01      | `http://localhost:8080`                     |
| wordpress-01      | `http://localhost:8081`                     |
| nodejs-01         | `http://localhost:8082`                     |
| vps-01 (SSH)      | `ssh admin@localhost -p 2222`               |
| vps-02 (SSH)      | `ssh admin@localhost -p 2223`               |

Mot de passe SSH par défaut : `debian_root_pass`

> Si un port est déjà utilisé, choisissez un port libre différent :
> `kubectl port-forward svc/wordpress-01-svc 8084:80`

---

## Commandes utiles

```bash
kubectl get pods
kubectl get services
kubectl get pvc
kubectl logs deployment/<nom-instance>
kubectl exec -it deployment/<nom-instance> -- bash

# Stopper tous les port-forwards actifs
kill $(pgrep -f 'kubectl port-forward')

# Vérifier quel processus utilise un port
lsof -i :<port>
```

---

## Tout supprimer

```powershell
terraform destroy
kind delete cluster --name hosting-local
```
