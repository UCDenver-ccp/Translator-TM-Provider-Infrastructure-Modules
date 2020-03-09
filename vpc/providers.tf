provider "google" {
  version = "~> 2.20.2"
  credentials = file(var.credentials)
  project     = var.project
  region      = var.region
}

provider "google-beta" {
  version = "~> 2.20.2"
  credentials = file(var.credentials)
  project     = var.project
  region      = var.region
}
