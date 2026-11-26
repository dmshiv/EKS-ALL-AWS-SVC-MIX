output "system_node_group_name" {
  description = "Name of the system managed node group."
  value       = aws_eks_node_group.system.node_group_name
}

output "launch_template_id" {
  description = "Launch template used by the system node group."
  value       = aws_launch_template.system.id
}
