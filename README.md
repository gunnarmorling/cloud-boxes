# Hetzner Node Set-Up

Sets up some nodes in the Hetzner cloud for demo purposes, using the [Hetzner Cloud provider](https://www.terraform.io/docs/providers/hcloud/r/server.html) for Terraform.

## Prerequisites

* [Terraform](https://www.terraform.io/) installed
* [Hetzner Cloud API](https://docs.hetzner.cloud/) token obtained and exported via `export TF_VAR_hcloud_token=<YOUR TOKEN>`
* [Ansible](https://www.ansible.com/) installed (for provisioning the box with Docker, Java etc.)
* Optional: [Vagrant](https://www.vagrantup.com/) and [VirtualBox](https://www.virtualbox.org/) installed for local set-up

## Set-Up

Run this once after a fresh check out:

* `terraform init`

## Running

Run this to provision the environment after adjusting the _terraform.tf_ file as needed:

* `terraform apply`

## Provisioning Docker etc.

* Edit _hosts_ to contain the right IP address and key file name
* `ansible-playbook -i hosts --limit=hetzner playbook.yml`

This also can be run against EC2, provided an instance has been set up
(see https://alt.fedoraproject.org/cloud/, "Standard HVM AMIs"):

* `ansible-playbook -i hosts --limit=aws playbook.yml`

Terraform set-up for that tbd.

## Local Set-Up via Vagrant

The Ansible set-up can also be used to provision a local VM via Vagrant and VirtualBox:

* `vagrant up --provision`

Subsequently, Ansible can also be run directly after changes to the playbook:

* `ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory playbook.yml`
