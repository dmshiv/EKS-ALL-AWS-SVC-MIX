output "service_network_id" {
  description = "Lattice service network id (referenced by the Gateway API controller config)."
  value       = var.enable_lattice ? aws_vpclattice_service_network.this[0].id : ""
}
