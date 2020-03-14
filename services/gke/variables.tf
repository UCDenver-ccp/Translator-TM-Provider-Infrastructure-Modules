# This code borrows heavily (completely) from:
# https://github.com/gruntwork-io/terraform-google-gke/blob/master/variables.tf

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables are expected to be passed in by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "credentials" {
  description = "The path to the service account credentials json file."
  type        = string
}

variable "project" {
  description = "The project ID where all resources will be launched."
  type        = string
}

variable "location" {
  description = "The location (region or zone) of the GKE cluster."
  type        = string
}

variable "region" {
  description = "The region for the network. If the cluster is regional, this must be the same region. Otherwise, it should be the region of the zone."
  type        = string
}

variable "bucket" {
  description = "The bucket storing terraform state."
  type        = string
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "The name of the Kubernetes cluster."
  type        = string
  default     = "tm-provider-cluster"
}

variable "cluster_service_account_name" {
  description = "The name of the custom service account used for the GKE cluster. This parameter is limited to a maximum of 28 characters."
  type        = string
  default     = "tm-provider-cluster-sa"
}

variable "cluster_service_account_description" {
  description = "A description of the custom service account used for the GKE cluster."
  type        = string
  default     = "GKE Cluster Service Account managed by Terraform for the Text Mining provider cluster"
}

# Kubectl options

variable "kubectl_config_path" {
  description = "Path to the kubectl config file. Defaults to $HOME/.kube/config"
  type        = string
  default     = ""
}

# Tiller TLS  settings

variable "tls_subject" {
  description = "The issuer information that contains the identifying information for the Tiller server. Used to generate the TLS certificate keypairs."
  type        = map(string)

  default = {
    common_name = "tiller"
    org         = "Gruntwork"
  }
  # Expects the following keys
  # - common_name (required)
  # - org (required)
  # - org_unit
  # - city
  # - state
  # - country
}

variable "client_tls_subject" {
  description = "The issuer information that contains the identifying information for the helm client of the operator. Used to generate the TLS certificate keypairs."
  type        = map(string)

  default = {
    common_name = "admin"
    org         = "Gruntwork"
  }
  # Expects the following keys
  # - common_name (required)
  # - org (required)
  # - org_unit
  # - city
  # - state
  # - country
}

# TLS algorithm configuration

variable "private_key_algorithm" {
  description = "The name of the algorithm to use for private keys. Must be one of: RSA or ECDSA."
  type        = string
  default     = "ECDSA"
}

variable "private_key_ecdsa_curve" {
  description = "The name of the elliptic curve to use. Should only be used if var.private_key_algorithm is ECDSA. Must be one of P224, P256, P384 or P521."
  type        = string
  default     = "P256"
}

variable "private_key_rsa_bits" {
  description = "The size of the generated RSA key in bits. Should only be used if var.private_key_algorithm is RSA."
  type        = number
  default     = 2048
}

# Tiller undeploy options

variable "force_undeploy" {
  description = "If true, will remove the Tiller server resources even if there are releases deployed."
  type        = bool
  default     = false
}

variable "undeploy_releases" {
  description = "If true, will delete deployed releases from the Tiller instance before undeploying Tiller."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation (size must be /28) to use for the hosted master network. This range will be used for assigning internal IP addresses to the master or set of masters, as well as the ILB VIP. This range must not overlap with any other ranges in use within the cluster's network."
  type        = string
  default     = "10.5.0.0/28"
}
