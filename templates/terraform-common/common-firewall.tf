# ==============================================================================
# COMMON FIREWALL CONFIGURATION
# This file contains shared firewall port definitions and structures used across all cloud providers
# ==============================================================================

locals {
  # Common firewall ports for Exasol cluster
  # These ports are required for Exasol cluster operation
  exasol_firewall_ports = {
    22    = "SSH access"
    2581  = "Default bucketfs"
    8443  = "Exasol Admin UI"
    8563  = "Default Exasol database connection"
    20002 = "Exasol container ssh"
    20003 = "Exasol confd API"
  }

  # Standardized firewall rule structure for providers that need priority/name
  # This provides a common base that can be adapted by each provider
  exasol_firewall_rules = {
    100 = { port = 22, name = "SSH" }
    110 = { port = 8563, name = "Exasol-Database" }
    120 = { port = 8443, name = "Exasol-AdminUI" }
    130 = { port = 2581, name = "Exasol-BucketFS" }
    140 = { port = 20002, name = "Exasol-ContainerSSH" }
    150 = { port = 20003, name = "Exasol-ConfdAPI" }
  }
}