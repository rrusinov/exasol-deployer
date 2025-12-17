variable "libvirt_memory_gb" {
  description = "Memory per VM in GB for libvirt provider."
  type        = number
  default     = 4
}

variable "libvirt_vcpus" {
  description = "Number of virtual CPUs per VM for libvirt provider."
  type        = number
  default     = 2
}

variable "libvirt_network_bridge" {
  description = "Libvirt network name (e.g., 'default' which typically uses virbr0 bridge)."
  type        = string
  default     = "default"
}

variable "libvirt_disk_pool" {
  description = "Storage pool name for libvirt provider."
  type        = string
  default     = "default"
}

variable "libvirt_uri" {
  description = "Libvirt connection URI (required; exasol init populates it via --libvirt-uri or virsh)."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.libvirt_uri) != "" && length(regexall("session", var.libvirt_uri)) == 0
    error_message = "libvirt_uri must be provided and must not be a session URI. Use qemu:///system locally or qemu+ssh://user@host/system remotely."
  }
}


variable "libvirt_domain_type" {
  description = "Domain type for libvirt (kvm only)."
  type        = string
  default     = "kvm"

  validation {
    condition     = var.libvirt_domain_type == "kvm"
    error_message = "Only libvirt domain type 'kvm' is supported."
  }
}

variable "libvirt_firmware" {
  description = "Firmware to use for libvirt domains (e.g., \"efi\" on Linux/KVM). Leave empty to let libvirt select the default."
  type        = string
  default     = ""
}
