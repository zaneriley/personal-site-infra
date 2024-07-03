variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  default     = ""
}

variable "ssh_key_fingerprint" {
  description = "Fingerprint of the SSH key to use for the droplet"
  type        = string
  default     = ""
}
