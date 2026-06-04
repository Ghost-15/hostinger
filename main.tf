terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Mot de passe unique généré à chaque déploiement — partagé par tous les services
resource "random_password" "shared_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*?"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-hosting-local"
}

# ════════════════════════════════════════════════════
# MACHINE 1 — WORDPRESS MULTISITE
# Réseau de sites WordPress (subdirectory mode)
# MySQL partagé avec la machine 2
# ════════════════════════════════════════════════════
resource "kubernetes_persistent_volume_claim" "multisite_pvc" {
  metadata { name = "multisite-pvc" }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "2Gi" }
    }
  }
}

resource "kubernetes_deployment" "multisite" {
  metadata {
    name   = "wp-multisite"
    labels = { app = "multisite" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "multisite" } }
    template {
      metadata { labels = { app = "multisite" } }
      spec {
        container {
          name  = "wordpress"
          image = "wordpress:php8.2-apache"
          port  { container_port = 80 }

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "mysql-svc:3306"
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = var.mysql_multisite_db
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = var.mysql_user
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = random_password.shared_password.result
          }
          env {
            name  = "WORDPRESS_CONFIG_EXTRA"
            value = <<-EOT
              define('WP_ALLOW_MULTISITE', true);
              define('MULTISITE', true);
              define('SUBDOMAIN_INSTALL', false);
              define('DOMAIN_CURRENT_SITE', 'localhost');
              define('PATH_CURRENT_SITE', '/');
              define('SITE_ID_CURRENT_SITE', 1);
              define('BLOG_ID_CURRENT_SITE', 1);
              define('DB_HOST', 'mysql-svc:3306');
            EOT
          }

          volume_mount {
            name       = "multisite-data"
            mount_path = "/var/www/html"
          }
        }
        volume {
          name = "multisite-data"
          persistent_volume_claim { claim_name = "multisite-pvc" }
        }
      }
    }
  }
}

resource "kubernetes_service" "multisite" {
  metadata { name = "multisite-svc" }
  spec {
    selector = { app = "multisite" }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# MACHINE 2 — MYSQL (base pour WordPress)
# ════════════════════════════════════════════════════
resource "kubernetes_secret" "mysql_secret" {
  metadata { name = "mysql-secret" }
  data = {
    MYSQL_ROOT_PASSWORD = base64encode(random_password.shared_password.result)
  }
}

resource "kubernetes_config_map" "mysql_init" {
  metadata { name = "mysql-init" }
  data = {
    "init.sql" = <<-EOT
      CREATE DATABASE IF NOT EXISTS `${var.mysql_db}`;
      CREATE DATABASE IF NOT EXISTS `${var.mysql_multisite_db}`;
      CREATE USER IF NOT EXISTS '${var.mysql_user}'@'%' IDENTIFIED BY '${random_password.shared_password.result}';
      GRANT ALL PRIVILEGES ON `${var.mysql_db}`.* TO '${var.mysql_user}'@'%';
      GRANT ALL PRIVILEGES ON `${var.mysql_multisite_db}`.* TO '${var.mysql_user}'@'%';
      FLUSH PRIVILEGES;
    EOT
  }
}

resource "kubernetes_persistent_volume_claim" "mysql_pvc" {
  metadata { name = "mysql-pvc" }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
}

resource "kubernetes_deployment" "mysql" {
  metadata {
    name   = "mysql"
    labels = { app = "mysql" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "mysql" } }
    template {
      metadata { labels = { app = "mysql" } }
      spec {
        container {
          name  = "mysql"
          image = "mysql:8.0"
          port  { container_port = 3306 }
          env_from {
            secret_ref { name = "mysql-secret" }
          }
          volume_mount {
            name       = "mysql-init"
            mount_path = "/docker-entrypoint-initdb.d/init.sql"
            sub_path   = "init.sql"
            read_only  = true
          }
          volume_mount {
            name       = "mysql-data"
            mount_path = "/var/lib/mysql"
          }
        }
        volume {
          name = "mysql-init"
          config_map { name = "mysql-init" }
        }
        volume {
          name = "mysql-data"
          persistent_volume_claim { claim_name = "mysql-pvc" }
        }
      }
    }
  }
}

resource "kubernetes_service" "mysql" {
  metadata { name = "mysql-svc" }
  spec {
    selector = { app = "mysql" }
    port {
      port        = 3306
      target_port = 3306
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# MACHINE 2 — WORDPRESS (avec MySQL)
# ════════════════════════════════════════════════════
resource "kubernetes_persistent_volume_claim" "wp_pvc" {
  metadata { name = "wp-pvc" }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
}

resource "kubernetes_deployment" "wordpress" {
  metadata {
    name   = "wordpress"
    labels = { app = "wordpress" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "wordpress" } }
    template {
      metadata { labels = { app = "wordpress" } }
      spec {
        container {
          name  = "wordpress"
          image = "wordpress:php8.2-apache"
          port  { container_port = 80 }

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "mysql-svc:3306"
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = var.mysql_db
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = var.mysql_user
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = random_password.shared_password.result
          }
          env {
            name  = "WORDPRESS_CONFIG_EXTRA"
            value = "define('WP_ALLOW_MULTISITE', true);"
          }

          volume_mount {
            name       = "wp-data"
            mount_path = "/var/www/html"
          }
        }
        volume {
          name = "wp-data"
          persistent_volume_claim { claim_name = "wp-pvc" }
        }
      }
    }
  }
}

resource "kubernetes_service" "wordpress" {
  metadata { name = "wordpress-svc" }
  spec {
    selector = { app = "wordpress" }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# MACHINE 3 — SERVEUR NODE.JS
# ════════════════════════════════════════════════════
resource "kubernetes_config_map" "nodejs_app" {
  metadata {
    name      = "nodejs-app"
    namespace = "default"
  }
  data = {
    "server.js" = <<-EOT
      const http = require('http');
      const os   = require('os');
      const server = http.createServer((req, res) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          status: 'OK',
          service: 'Node.js Server',
          hostname: os.hostname(),
          timestamp: new Date().toISOString(),
          path: req.url
        }));
      });
      server.listen(3000, () => console.log('Node.js running on port 3000'));
    EOT
  }
}

resource "kubernetes_deployment" "nodejs" {
  metadata {
    name   = "nodejs-server"
    labels = { app = "nodejs" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "nodejs" } }
    template {
      metadata { labels = { app = "nodejs" } }
      spec {
        container {
          name  = "nodejs"
          image = "node:20-alpine"
          command = ["node", "/app/server.js"]
          port  { container_port = 3000 }
          volume_mount {
            name       = "app-code"
            mount_path = "/app"
          }
        }
        volume {
          name = "app-code"
          config_map { name = "nodejs-app" }
        }
      }
    }
  }
}

resource "kubernetes_service" "nodejs" {
  metadata { name = "nodejs-svc" }
  spec {
    selector = { app = "nodejs" }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# MACHINE 4 — VPS DEBIAN (SSH accessible)
# ════════════════════════════════════════════════════
resource "kubernetes_deployment" "debian_vps" {
  metadata {
    name   = "debian-vps"
    labels = { app = "debian-vps" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "debian-vps" } }
    template {
      metadata { labels = { app = "debian-vps" } }
      spec {
        container {
          name  = "debian"
          image = "lscr.io/linuxserver/openssh-server:latest"
          port  { container_port = 2222 }

          env {
            name  = "PUID"
            value = "1000"
          }
          env {
            name  = "PGID"
            value = "1000"
          }
          env {
            name  = "PASSWORD_ACCESS"
            value = "true"
          }
          env {
            name  = "USER_NAME"
            value = "admin"
          }
          env {
            name  = "USER_PASSWORD"
            value = random_password.shared_password.result
          }
          env {
            name  = "SUDO_ACCESS"
            value = "true"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "debian_vps" {
  metadata { name = "debian-vps-svc" }
  spec {
    selector = { app = "debian-vps" }
    port {
      port        = 2222
      target_port = 2222
    }
    type = "ClusterIP"
  }
}
