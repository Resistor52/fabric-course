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

variable "code_server_password" {
  description = "Password for code-server"
  type        = string
  sensitive   = true
} 