variable "mysql_db" {
  description = "Nom de la base MySQL pour WordPress (site unique)"
  type        = string
  default     = "wordpress_db"
}

variable "mysql_multisite_db" {
  description = "Nom de la base MySQL pour WordPress Multisite"
  type        = string
  default     = "wordpress_multisite_db"
}

variable "mysql_user" {
  description = "Utilisateur MySQL"
  type        = string
  default     = "wp_user"
}

variable "mysql_password" {
  description = "Mot de passe MySQL"
  type        = string
  default     = "wp_secret_pass"
  sensitive   = true
}

variable "mysql_root_password" {
  description = "Mot de passe root MySQL"
  type        = string
  default     = "mysql_root_pass"
  sensitive   = true
}

variable "vps_root_password" {
  description = "Mot de passe root du VPS Debian"
  type        = string
  default     = "debian_root_pass"
  sensitive   = true
}
