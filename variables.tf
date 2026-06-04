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
  description = "Utilisateur MySQL partagé"
  type        = string
  default     = "wp_user"
}
