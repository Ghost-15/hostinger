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

variable "mysql_user" {
  description = "Utilisateur MySQL partagé"
  type        = string
  default     = "wp_user"
}
