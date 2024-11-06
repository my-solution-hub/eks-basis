variable "region" {
  # set default to singapore region
  default = "ap-southeast-1"
}

variable "cluster_name" {
  default = "demo"
}

variable "username" {
  default = "yagrxu"
}

variable "grafana_username" {
  default = "yagrxu@amazon.com"
}

variable "sso_region" {
  default = "ap-southeast-1"
}

variable "ebs_csi_driver_version" {
  default = "v1.33.0-eksbuild.1"
}

variable "vpc_cidr_prefix" {
  default = "10.0"
}