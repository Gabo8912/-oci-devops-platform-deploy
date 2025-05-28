/*
  Updated oke.tf to use an existing cluster via data source instead of creating new one.
*/

# Lee un clúster OKE existente
data "oci_containerengine_cluster" "existing" {
  cluster_id = var.existent_oke_cluster_id
}

# Opcional: crea un nuevo clúster solo si create_new_oke_cluster = true
resource "oci_containerengine_cluster" "oke_cluster" {
  count              = var.create_new_oke_cluster ? 1 : 0
  compartment_id     = local.oke_compartment_id
  kubernetes_version = (var.k8s_version == "Latest")
    ? local.cluster_k8s_latest_version
    : var.k8s_version
  name    = "${var.app_name} (${random_string.deploy_id.result})"
  vcn_id  = oci_core_virtual_network.oke_vcn[0].id

  endpoint_config {
    is_public_ip_enabled = var.cluster_endpoint_visibility == "Private" ? false : true
    subnet_id            = oci_core_subnet.oke_k8s_endpoint_subnet[0].id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.oke_lb_subnet[0].id]
    add_ons {
      is_kubernetes_dashboard_enabled = var.cluster_options_add_ons_is_kubernetes_dashboard_enabled
      is_tiller_enabled               = false
    }
    admission_controller_options {
      is_pod_security_policy_enabled = var.cluster_options_admission_controller_options_is_pod_security_policy_enabled
    }
    kubernetes_network_config {
      services_cidr = lookup(var.network_cidrs, "KUBERNETES-SERVICE-CIDR")
      pods_cidr     = lookup(var.network_cidrs, "PODS-CIDR")
    }
  }
}

# Crea el node pool según si generas un clúster nuevo o usas el existente
resource "oci_containerengine_node_pool" "oke_node_pool" {
  count = var.create_new_oke_cluster ? 1 : 0

  cluster_id = var.create_new_oke_cluster
    ? oci_containerengine_cluster.oke_cluster[0].id
    : data.oci_containerengine_cluster.existing.id

  compartment_id     = local.oke_compartment_id
  kubernetes_version = (var.k8s_version == "Latest")
    ? local.node_pool_k8s_latest_version
    : var.k8s_version
  name           = var.node_pool_name
  node_shape     = var.node_pool_shape
  ssh_public_key = var.generate_public_ssh_key
    ? tls_private_key.oke_worker_node_ssh_key.public_key_openssh
    : var.public_ssh_key

  node_config_details {
    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ADs.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.oke_nodes_subnet[0].id
      }
    }
    size = var.num_pool_workers
  }

  dynamic "node_shape_config" {
    for_each = local.is_flexible_node_shape ? [1] : []
    content {
      ocpus         = var.node_pool_node_shape_config_ocpus
      memory_in_gbs = var.node_pool_node_shape_config_memory_in_gbs
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = lookup(data.oci_core_images.node_pool_images.images[0], "id")
    boot_volume_size_in_gbs = var.node_pool_boot_volume_size_in_gbs
  }

  initial_node_labels {
    key   = "name"
    value = var.node_pool_name
  }
}
