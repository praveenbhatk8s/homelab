output "cluster_id" {
  description = "ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer for workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity, for granting image pull on the registry."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "private_cluster" {
  description = "True when the API server is private."
  value       = azurerm_kubernetes_cluster.this.private_cluster_enabled
}

output "zones" {
  description = "Zones the node pools span."
  value       = var.zones
}
