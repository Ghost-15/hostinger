output "wordpress_port_forwards" {
  description = "Commandes port-forward pour les instances WordPress"
  value = {
    for name, cfg in var.wordpress_instances :
    name => "kubectl port-forward svc/${name}-svc ${cfg.port}:80"
  }
}

output "multisite_port_forwards" {
  description = "Commandes port-forward pour les instances WordPress Multisite"
  value = {
    for name, cfg in var.multisite_instances :
    name => "kubectl port-forward svc/${name}-svc ${cfg.port}:80"
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
