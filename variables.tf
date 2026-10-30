variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "ciso_assistant_version" {
  type        = string
  default     = "v4.1.5"
  description = "Tag of the ghcr.io/intuitem/ciso-assistant-community backend and frontend images, such as \"v4.1.5\". Change backend_image_digest and frontend_image_digest with it."

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", var.ciso_assistant_version))
    error_message = "ciso_assistant_version must be an image tag, such as \"v4.1.5\"."
  }
}

variable "backend_image_digest" {
  type        = string
  default     = "sha256:bf33509874da045a8d41c27b9a6c74113ecd7ff5e04378b1995ea9e137e9b707"
  description = "Digest of the backend image for ciso_assistant_version. Podman pulls by the digest, so a tag that moves upstream can't change what runs."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.backend_image_digest))
    error_message = "backend_image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "frontend_image_digest" {
  type        = string
  default     = "sha256:9a4016e2aa9bb4ca5070e112ec92610c5fcc4872a332efcc74dec6569f48fd9b"
  description = "Digest of the frontend image for ciso_assistant_version."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.frontend_image_digest))
    error_message = "frontend_image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "public_url" {
  type        = string
  description = "The address people reach CISO Assistant at, with no path or trailing slash, such as \"https://grc.example.com\". The app sets its allowed host and its links from it."

  validation {
    condition     = can(regex("^https?://[^\\s/]+$", var.public_url))
    error_message = "public_url must be an http or https URL with no path or trailing slash, such as \"https://grc.example.com\"."
  }
}

variable "db_host" {
  type        = string
  default     = "127.0.0.1"
  description = "Address of the PostgreSQL server, as seen from the host."
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "Port of the PostgreSQL server."
}

variable "db_name" {
  type        = string
  default     = "ciso_assistant"
  description = "Name of the database, which has to exist already."
}

variable "db_user" {
  type        = string
  default     = "ciso_assistant"
  description = "PostgreSQL role that owns the database."
}

variable "db_password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Password of db_user. It reaches the host in root-only files and never the plan or state."

  validation {
    condition     = length(var.db_password) > 0 && !strcontains(var.db_password, "\n")
    error_message = "db_password must be one line and not empty."
  }
}

variable "admin_email" {
  type        = string
  description = "Email address of the first administrator, who signs in with admin_password."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.admin_email))
    error_message = "admin_email must be an email address, such as \"you@example.com\"."
  }
}

variable "admin_password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Password of the first administrator. It reaches the host in a root-only file and never the plan or state. CISO Assistant sets it only when it creates the user."

  validation {
    condition     = length(var.admin_password) >= 12 && !strcontains(var.admin_password, "\n")
    error_message = "admin_password must be at least 12 characters on one line."
  }
}

variable "listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address the web interface listens on. The default keeps it on the host for a reverse proxy in front; \"0.0.0.0\" listens on every address."

  validation {
    condition     = can(cidrhost("${var.listen_address}/${strcontains(var.listen_address, ":") ? 128 : 32}", 0))
    error_message = "listen_address must be an IPv4 or IPv6 address, such as \"127.0.0.1\"."
  }
}

variable "port" {
  type        = number
  default     = 3000
  description = "Port the web interface listens on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "backend_port" {
  type        = number
  default     = 8000
  description = "Port the API listens on, always on 127.0.0.1."

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535 && floor(var.backend_port) == var.backend_port
    error_message = "backend_port must be a whole number from 1 to 65535."
  }
}

variable "min_memory_mb" {
  type        = number
  default     = 3500
  description = "Memory, in MiB, a host needs before the circuit configures it. A 4 GB host reports a little less than 4096."

  validation {
    condition     = var.min_memory_mb >= 0
    error_message = "min_memory_mb can't be negative."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "More of CISO Assistant's environment variables for the backend and the worker, such as { EMAIL_HOST = \"smtp.example.com\", EMAIL_HOST_PASSWORD = \"...\" }. They go in root-only files and never reach the plan or state."

  validation {
    condition     = alltrue([for k, v in var.environment : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !strcontains(v, "\n")])
    error_message = "environment maps variable names, such as EMAIL_HOST, to values on one line."
  }

  validation {
    condition     = length([for k in keys(var.environment) : k if contains(["ALLOWED_HOSTS", "CISO_ASSISTANT_URL", "DJANGO_DEBUG", "DJANGO_SECRET_KEY", "POSTGRES_NAME", "POSTGRES_USER", "POSTGRES_PASSWORD", "DB_HOST", "DB_PORT", "PORT", "HOME"], k) || startswith(k, "DJANGO_SUPERUSER_") || startswith(k, "XDG_")]) == 0
    error_message = "Variables the circuit sets itself aren't allowed in environment: the hosts and URL, debug, the secret key, the database settings, PORT, HOME, XDG_* and DJANGO_SUPERUSER_*."
  }
}
