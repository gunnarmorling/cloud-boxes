# Hetzer Node Set-Up

Sets up some nodes in the Hetzner cloud for demo purposes, using the [Hetzner Cloud provider](https://www.terraform.io/docs/providers/hcloud/r/server.html) for Terraform.

## Prerequisites

* [Terraform](https://www.terraform.io/) installed
* [Hetzner Cloud API](https://docs.hetzner.cloud/) token obtained and exported via `export TF_VAR_hcloud_token=<YOUR TOKEN>`

## Set-Up

Run this once after a fresh check out:

* `terraform init`

## Running

Run this to provision the environment after adjusting the _terraform.tf_ file as needed:

* `terraform apply`
