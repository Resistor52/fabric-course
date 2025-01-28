variable "domain" {
  description = "DuckDNS domain"
  type        = string
}

variable "email" {
  description = "Email for Let's Encrypt"
  type        = string
}

variable "duckdns_token" {
  description = "DuckDNS token"
  type        = string
  sensitive   = true
}

variable "number_of_users" {
  description = "Number of student users to create"
  type        = number
  default     = 10
}

variable "ssh_key_name" {
  description = "Name of the AWS key pair to use for EC2 instances"
  type        = string
}

variable "ssh_pem_file" {
  description = "Full path to the SSH PEM file for connecting to instances"
  type        = string
} 