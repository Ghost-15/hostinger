variable "mysql_root_password" {
  description = "Mot de passe root MySQL"
  type        = string
  sensitive   = true
}

# ─────────────────────────────────────────────
# Instances WordPress (site unique)
# ─────────────────────────────────────────────
variable "wordpress_instances" {
  description = "Map des instances WordPress. Clé = nom de l'instance."
  type = map(object({
    db_name = string
    db_user = string
    db_pass = string
    port    = number
  }))
}

# ─────────────────────────────────────────────
# Instances WordPress Multisite
# ─────────────────────────────────────────────
variable "multisite_instances" {
  description = "Map des instances WordPress Multisite. Clé = nom de l'instance."
  type = map(object({
    db_name = string
    db_user = string
    db_pass = string
    port    = number
  }))
}

# ─────────────────────────────────────────────
# Instances Node.js
# ─────────────────────────────────────────────
variable "nodejs_instances" {
  description = "Map des instances Node.js. Clé = nom de l'instance."
  type = map(object({
    port = number
  }))
}

# ─────────────────────────────────────────────
# Instances VPS Debian SSH
# ─────────────────────────────────────────────
variable "vps_instances" {
  description = "Map des instances VPS Debian SSH. Clé = nom de l'instance."
  type = map(object({
    password = string
    ssh_port = number
  }))
}
