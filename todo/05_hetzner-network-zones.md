# Wire Hetzner Network Zones End-to-End (LATER)

## Issue
`hetzner_network_zone` is defined in `templates/terraform-hetzner/variables.tf` but `main.tf` hardcodes `"eu-central"` for the subnet and `cmd_init`/README never expose the option. Users cannot choose zones such as `us-east`.

## Recommendation
Add a `--hetzner-network-zone` flag in `lib/cmd_init.sh`, pass it through `write_provider_variables`, document it in `README.md`, and use `var.hetzner_network_zone` for `hcloud_network_subnet.network_zone`.

## Next Steps
1. Update CLI help, Terraform variables file generation, and the Hetzner template
2. Add tests/validation ensuring non-default zones apply correctly

## Documentation

A network zone in Hetzner Cloud groups data‑center locations. Hetzner currently has four zones: eu‑central, us‑east, us‑west and ap‑southeast. Each zone contains one or more physical locations (e.g. eu‑central includes Falkenstein fsn1, Helsinki hel1 and Nuremberg nbg1; us‑west is Hillsboro hil; us‑east is Ashburn ash; ap‑southeast is Singapore sin)
docs.hetzner.com
. All resources in a network—servers, subnets, load‑balancers, floating IPs—must belong to the same network zone, otherwise they cannot be attached
docs.hetzner.com
. Hetzner’s network FAQ explains that locations within a network must be from the same zone and lists the zone‑to‑location mapping
docs.hetzner.com
.

What hetzner_network_zone represents

In a Terraform module, a variable such as hetzner_network_zone (sometimes simply named network_zone) holds the name of the network zone. The variable in the template shown below has a default value of “eu‑central”
raw.githubusercontent.com
:

variable "network_zone" {
  description = "Name of the Hetzner network zone"
  type        = string
  default     = "eu-central"
}


Many Hetzner resources (e.g., hcloud_network_subnet or hcloud_load_balancer) require this string. The official provider documentation describes the network_zone argument as Required and notes that its value is the name of the zone
devopsschool.com
.

How to set it in Terraform

Choose the correct zone based on your server location(s). The zone must correspond to all the locations used by your servers and subnets. For instance, if your servers are deployed in the nbg1 (Nuremberg) data‑center, you must set the network zone to eu-central, because that zone includes Nuremberg, Falkenstein and Helsinki
oghabi.it
. If you plan to deploy in Ashburn you would set it to us-east, and for Hillsboro to us-west. Mixing locations from different zones in the same network is not permitted
docs.hetzner.com
.

Pass the variable to resources. Within your Terraform template, assign this variable to the network_zone argument of hcloud_network_subnet and other resources that need it. For example:

variable "hetzner_network_zone" {
  description = "Hetzner network zone"
  type        = string
  default     = "eu-central"
}

resource "hcloud_network" "private_net" {
  name     = var.network_name
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "private_subnet" {
  network_id   = hcloud_network.private_net.id
  type         = "cloud"
  network_zone = var.hetzner_network_zone  # e.g. "eu-central", "us-east"
  ip_range     = "10.0.1.0/24"
}


Match the zone with load balancers, floating IPs and volumes. When creating load balancers or floating IPs, either specify a location or set the same network_zone; if you leave out the location, the provider will use the zone to choose an appropriate data‑center. Ensure that any resource (server, subnet, volume, load‑balancer, floating IP) you attach shares the same zone, otherwise Terraform will fail to attach them.

Adjust when deploying outside Europe. Hetzner’s U.S. and Singapore zones have different prices and availability
docs.hetzner.com
, so set hetzner_network_zone to us-east, us-west or ap-southeast only when you intentionally deploy to those regions.

In summary, hetzner_network_zone is simply the string name of the Hetzner Cloud network zone (eu‑central, us‑east, us‑west or ap‑southeast) and must be set consistently across all Hetzner resources in your Terraform configuration. Choose the zone that corresponds to your intended server locations, assign it to the network_zone argument in resources such as hcloud_network_subnet, and avoid mixing zones within the same private network