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

output "multisite_port_forwards" {
  description = "Commandes port-forward pour les instances WordPress Multisite"
  value = {
    "1_wp_multisite" = "kubectl port-forward svc/multisite-svc   8080:80"
    "2_wordpress"    = "kubectl port-forward svc/wordpress-svc   8081:80"
    "3_nodejs"       = "kubectl port-forward svc/nodejs-svc      8082:3000"
    "4_debian_ssh"   = "kubectl port-forward svc/debian-vps-svc  2222:2222"
  }
}

output "nodejs_port_forwards" {
  description = "Commandes port-forward pour les instances Node.js"
  value = {
    for name, cfg in var.nodejs_instances :
    name => "kubectl port-forward svc/${name}-svc ${cfg.port}:3000"
  }
}

output "vps_port_forwards" {
  description = "Commandes port-forward pour les instances VPS Debian"
  value = {
    for name, cfg in var.vps_instances :
    name => "kubectl port-forward svc/${name}-svc ${cfg.ssh_port}:2222  # ssh admin@localhost -p ${cfg.ssh_port}"
  }
}
