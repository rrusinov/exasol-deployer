# GCP-specific outputs in addition to common outputs
output "project_id" {
  description = "The GCP project ID"
  value       = var.gcp_project
}

output "node_names" {
  description = "Names of all nodes"
  value       = google_compute_instance.exasol_node[*].name
}
