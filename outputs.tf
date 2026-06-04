output "shared_password" {
  description = "Mot de passe généré — commun à tous les services"
  value       = random_password.shared_password.result
  sensitive   = true
}

output "services" {
  description = "Résumé des services déployés"
  value = {
    wp_multisite = "http://localhost:8080       (WordPress Multisite — user: wp_user)"
    wordpress    = "http://localhost:8081       (WordPress — user: wp_user)"
    nodejs       = "http://localhost:8082       (API Node.js)"
    debian_vps   = "ssh admin@localhost -p 2222 (VPS Debian SSH)"
    mysql        = "localhost:3306             (MySQL root + user: wp_user)"
  }
}

output "port_forward_commands" {
  description = "Commandes port-forward à lancer dans des terminaux séparés"
  value = {
    "1_wp_multisite" = "kubectl port-forward svc/multisite-svc   8080:80"
    "2_wordpress"    = "kubectl port-forward svc/wordpress-svc   8081:80"
    "3_nodejs"       = "kubectl port-forward svc/nodejs-svc      8082:3000"
    "4_debian_ssh"   = "kubectl port-forward svc/debian-vps-svc  2222:2222"
  }
}

output "wp_multisite_setup" {
  description = "Étapes pour finaliser le WordPress Multisite"
  value = <<-EOT
    1. Ouvrir http://localhost:8080/wp-admin
    2. Aller dans Outils > Configuration du réseau
    3. Choisir "Sous-répertoires" (subdirectory)
    4. Suivre les instructions pour activer le réseau
    5. Ajouter des sites via Mes Sites > Administration réseau > Sites
  EOT
}
