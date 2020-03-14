# -----------------------------------------------------------------------------
# DEPLOY A GKE PRIVATE CLUSTER IN GOOGLE CLOUD PLATFORM
# This code borrows heavily from:
# https://github.com/gruntwork-io/terraform-google-gke/blob/v0.4.0/examples/gke-private-cluster/main.tf
# -----------------------------------------------------------------------------


terraform {

  # Partial configuration for the backend: https://www.terraform.io/docs/backends/config.html#partial-configuration
  # In this case, the backend configuration will be filled in by Terragrunt
  backend "gcs" {}

  # Only allow this Terraform version. Note that if you upgrade to a newer version, Terraform won't allow you to use an
  # older version, so when you upgrade, you should upgrade everyone on your team and your CI servers all at once.
  required_version = ">= 0.12.19"

  required_providers {
    google = "~> 2.20.2"
  }
}

# -----------------------------------------------------------------------------
# Connect to the VPC terraform state so that the already created network
# configuration can be extracted and used to configure the GKE cluster
# -----------------------------------------------------------------------------
data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = {
    bucket      = var.bucket
    prefix      = "vpc"
    credentials = var.credentials
  }
}

# -----------------------------------------------------------------------------
# DEPLOY A PRIVATE CLUSTER IN GOOGLE CLOUD PLATFORM
# -----------------------------------------------------------------------------

module "gke_cluster" {
  source = "github.com/gruntwork-io/terraform-google-gke.git//modules/gke-cluster?ref=v0.4.0"

  name = var.cluster_name

  project  = var.project
  location = var.location
  network  = data.terraform_remote_state.vpc.outputs.vpc_network.network

  # We're deploying the cluster in the 'public' subnetwork to allow outbound internet access
  # See the network access tier table for full details:
  # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
  subnetwork = data.terraform_remote_state.vpc.outputs.vpc_network.public_subnetwork

  # When creating a private cluster, the 'master_ipv4_cidr_block' has to be defined and the size must be /28
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # This setting will make the cluster private
  enable_private_nodes = "true"

  # To make testing easier, we keep the public endpoint available. In production, we highly recommend restricting access to only within the network boundary, requiring your users to use a bastion host or VPN.
  disable_public_endpoint = "false"

  # With a private cluster, it is highly recommended to restrict access to the cluster master
  # However, for testing purposes we will allow all inbound traffic.
  master_authorized_networks_config = [
    {
      cidr_blocks = [
        {
          cidr_block   = "0.0.0.0/0"
          display_name = "all-for-testing"
        },
      ]
    },
  ]

  cluster_secondary_range_name = data.terraform_remote_state.vpc.outputs.vpc_network.public_subnetwork_secondary_range_name
}

# -----------------------------------------------------------------------------
# CREATE A CUSTOM SERVICE ACCOUNT TO USE WITH THE GKE CLUSTER
# -----------------------------------------------------------------------------

module "gke_service_account" {
  source = "github.com/gruntwork-io/terraform-google-gke.git//modules/gke-service-account?ref=v0.4.0"

  name        = var.cluster_service_account_name
  project     = var.project
  description = var.cluster_service_account_description
}

# -----------------------------------------------------------------------------
# CREATE A DEFAULT NODE POOL
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "node_pool" {
  provider = google-beta

  name     = "private-pool"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "1"

  autoscaling {
    min_node_count = "1"
    max_node_count = "5"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-pools-example = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-pool-example",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# -----------------------------------------------------------------------------
# CREATE A GPU NODE POOL
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "node_pool_gpu1" {
  provider = google-beta

  name     = "private-gpu-pool-1"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "12"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type        = "COS"
    machine_type      = "n1-standard-4"
    
    guest_accelerator {
      type  = "nvidia-tesla-k80"
      count = 1
    }
    
    labels = {
      private-gpu-pool = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-gpu-pool-1",
    ]

    disk_size_gb = "100"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}



# # Automatic installation of the Nvidia GPU drivers is problematic.
# # This block is currently commented out b/c it results in ambiguous
# # errors during the Terraform plan stage, e.g. connection refused or
# # some error related to unsigned certificates.
# # This plugin makes use of the default kubectl config, and therefore
# # requires the K8s cluster to be up and running, so it is not a good
# # candidate for installation via Terraform. The GPU drivers should be
# # installed manually using:
# #
# # kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml
# #
# # For details, see: 
# #     https://cloud.google.com/kubernetes-engine/docs/how-to/gpus#installing_drivers
# #
# # ---------------------------------------------------------------------------------------------------------------------
# # INSTALL THE NVIDIA DRIVER ON THE GPU NODES
# # Requires the following plugin to be installed locally:
# # https://github.com/banzaicloud/terraform-provider-k8s
# # ---------------------------------------------------------------------------------------------------------------------

# data "http" "nvidia-ds-config" {
#   url = "https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml"
# }

# resource "k8s_manifest" "nvidia-driver-daemonset" {
#   content   = data.http.nvidia-ds-config.body
##  depends_on = [
##    gke_cluster,
##  ]
# }


# ----------------------------------------------------
# create a node pool for the oger-chebi-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-chebi-ext" {
  provider = google-beta

  name     = "private-oger-pool-chebi-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-chebi-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-chebi-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-cl-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-cl-ext" {
  provider = google-beta

  name     = "private-oger-pool-cl-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-cl-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-cl-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-go-bp-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-go-bp-ext" {
  provider = google-beta

  name     = "private-oger-pool-go-bp-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-go-bp-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-go-bp-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-go-cc-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-go-cc-ext" {
  provider = google-beta

  name     = "private-oger-pool-go-cc-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-go-cc-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-go-cc-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-go-mf-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-go-mf-ext" {
  provider = google-beta

  name     = "private-oger-pool-go-mf-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-go-mf-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-go-mf-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-mop-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-mop-ext" {
  provider = google-beta

  name     = "private-oger-pool-mop-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-mop-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-mop-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-ncbitaxon-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-ncbitaxon-ext" {
  provider = google-beta

  name     = "private-oger-pool-ncbitaxon-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-4" # 15 GB RAM

    labels = {
      private-oger-pool-ncbitaxon-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-ncbitaxon-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-pr-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-pr-ext" {
  provider = google-beta

  name     = "private-oger-pool-pr-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-4" # 15 GB RAM

    labels = {
      private-oger-pool-pr-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-pr-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-so-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-so-ext" {
  provider = google-beta

  name     = "private-oger-pool-so-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-so-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-so-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ----------------------------------------------------
# create a node pool for the oger-uberon-ext service
# ----------------------------------------------------

resource "google_container_node_pool" "node-pool-oger-uberon-ext" {
  provider = google-beta

  name     = "private-oger-pool-uberon-ext"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "3"

  autoscaling {
    min_node_count = "0"
    max_node_count = "10"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-2" # 7.5 GB RAM

    labels = {
      private-oger-pool-uberon-ext = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      data.terraform_remote_state.vpc.outputs.vpc_network.private,
      "private-oger-pool-uberon-ext",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}



