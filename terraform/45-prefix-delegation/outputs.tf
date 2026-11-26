output "node_group_name" {
  description = "Prefix-delegation node group (empty when disabled)."
  value       = var.enable_prefix_delegation_nodegroup ? aws_eks_node_group.pd[0].node_group_name : ""
}

output "max_pods" {
  description = "kubelet maxPods configured on the node group."
  value       = var.max_pods
}
