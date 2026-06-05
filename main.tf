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
# MYSQL — instance unique partagée par tous les WP
# ════════════════════════════════════════════════════

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
          port { container_port = 3306 }
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
# WORDPRESS SITE UNIQUE — for_each sur wordpress_instances
# ════════════════════════════════════════════════════

resource "kubernetes_persistent_volume_claim" "wordpress" {
  for_each = var.wordpress_instances

  metadata { name = "${each.key}-pvc" }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
}

resource "kubernetes_deployment" "wordpress" {
  for_each = var.wordpress_instances

  metadata {
    name   = each.key
    labels = { app = each.key }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = each.key } }
    template {
      metadata { labels = { app = each.key } }
      spec {
        container {
          name  = "wordpress"
          image = "wordpress:php8.2-apache"
          port { container_port = 80 }

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "mysql-svc:3306"
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = each.value.db_name
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = each.value.db_user
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
          persistent_volume_claim { claim_name = "${each.key}-pvc" }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.mysql]
}

resource "kubernetes_service" "wordpress" {
  for_each = var.wordpress_instances

  metadata { name = "${each.key}-svc" }
  spec {
    selector = { app = each.key }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# WORDPRESS MULTISITE — for_each sur multisite_instances
# ════════════════════════════════════════════════════

resource "kubernetes_persistent_volume_claim" "multisite" {
  for_each = var.multisite_instances

  metadata { name = "${each.key}-pvc" }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "2Gi" }
    }
  }
}

resource "kubernetes_deployment" "multisite" {
  for_each = var.multisite_instances

  metadata {
    name   = each.key
    labels = { app = each.key }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = each.key } }
    template {
      metadata { labels = { app = each.key } }
      spec {
        container {
          name  = "wordpress"
          image = "wordpress:php8.2-apache"
          port { container_port = 80 }

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "mysql-svc:3306"
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = each.value.db_name
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = each.value.db_user
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = each.value.db_pass
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
            EOT
          }

          volume_mount {
            name       = "ms-data"
            mount_path = "/var/www/html"
          }
        }
        volume {
          name = "ms-data"
          persistent_volume_claim { claim_name = "${each.key}-pvc" }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.mysql]
}

resource "kubernetes_service" "multisite" {
  for_each = var.multisite_instances

  metadata { name = "${each.key}-svc" }
  spec {
    selector = { app = each.key }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# NODE.JS — for_each sur nodejs_instances
# ════════════════════════════════════════════════════

resource "kubernetes_config_map" "nodejs_app" {
  for_each = var.nodejs_instances

  metadata {
    name      = "${each.key}-code"
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
          service: '${each.key}',
          hostname: os.hostname(),
          timestamp: new Date().toISOString(),
          path: req.url
        }));
      });
      server.listen(3000, () => console.log('${each.key} running on port 3000'));
    EOT
  }
}

resource "kubernetes_deployment" "nodejs" {
  for_each = var.nodejs_instances

  metadata {
    name   = each.key
    labels = { app = each.key }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = each.key } }
    template {
      metadata { labels = { app = each.key } }
      spec {
        container {
          name    = "nodejs"
          image   = "node:20-alpine"
          command = ["node", "/app/server.js"]
          port { container_port = 3000 }
          volume_mount {
            name       = "app-code"
            mount_path = "/app"
          }
        }
        volume {
          name = "app-code"
          config_map { name = "${each.key}-code" }
        }
      }
    }
  }
}

resource "kubernetes_service" "nodejs" {
  for_each = var.nodejs_instances

  metadata { name = "${each.key}-svc" }
  spec {
    selector = { app = each.key }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }
}

# ════════════════════════════════════════════════════
# VPS DEBIAN SSH — for_each sur vps_instances
# ════════════════════════════════════════════════════

resource "kubernetes_deployment" "vps" {
  for_each = var.vps_instances

  metadata {
    name   = each.key
    labels = { app = each.key }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = each.key } }
    template {
      metadata { labels = { app = each.key } }
      spec {
        container {
          name  = "debian"
          image = "lscr.io/linuxserver/openssh-server:latest"
          port { container_port = 2222 }

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

resource "kubernetes_service" "vps" {
  for_each = var.vps_instances

  metadata { name = "${each.key}-svc" }
  spec {
    selector = { app = each.key }
    port {
      port        = 2222
      target_port = 2222
    }
    type = "ClusterIP"
  }
}
