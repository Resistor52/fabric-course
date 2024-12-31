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