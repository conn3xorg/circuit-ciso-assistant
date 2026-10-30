variable "port" {
  type    = number
  default = 2222
}

# Example passwords only. Pass your own with -var or TF_VAR_ on a real host.
variable "db_password" {
  type      = string
  default   = "correct-horse-battery"
  ephemeral = true
  sensitive = true
}

variable "admin_password" {
  type      = string
  default   = "audit-binder-lantern"
  ephemeral = true
  sensitive = true
}

locals {
  host = { box = "127.0.0.1" }
}

# PostgreSQL on the same host, listening only on localhost.
module "postgres" {
  source = "github.com/conn3xorg/circuit-postgres?ref=v0.2.0"

  hosts                = local.host
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  users          = ["ciso_assistant"]
  user_passwords = { ciso_assistant = var.db_password }
  databases      = { ciso_assistant = "ciso_assistant" }
}

module "ciso_assistant" {
  source = "../.."

  depends_on = [module.postgres]

  hosts                = local.host
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  public_url     = "http://localhost:3000"
  db_password    = var.db_password
  admin_email    = "admin@example.com"
  admin_password = var.admin_password
}
