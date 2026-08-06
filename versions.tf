terraform {
  required_version = ">= 1.5"

  # State lives in HCP Terraform. Set this workspace's execution mode to LOCAL
  # in the UI — otherwise HCP runs plans on its own runners, which cannot see
  # terraform.tfvars and will fail on a missing hcloud_token.
  cloud {
    organization = "leonard-zimdars"

    workspaces {
      name = "infra"
    }
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.68"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}
