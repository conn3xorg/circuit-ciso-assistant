locals {
  # The ghcr.io/intuitem/ciso-assistant-community/ path is the AGPL community
  # edition. Images directly under ghcr.io/intuitem/ are the commercial
  # edition, which needs a contract with intuitem.
  backend_image  = "ghcr.io/intuitem/ciso-assistant-community/backend:${var.ciso_assistant_version}@${var.backend_image_digest}"
  frontend_image = "ghcr.io/intuitem/ciso-assistant-community/frontend:${var.ciso_assistant_version}@${var.frontend_image_digest}"

  dir       = "/etc/ciso-assistant"
  keys_file = "${local.dir}/keys.env"

  public_host = regex("^https?://([^/:]+)", var.public_url)[0]

  # What the backend and the task worker both need, none of it secret. HOME
  # and the XDG paths point at /tmp because the root filesystem is read-only,
  # as in upstream's compose file.
  backend_env = {
    ALLOWED_HOSTS      = "${local.public_host},localhost,127.0.0.1"
    CISO_ASSISTANT_URL = var.public_url
    DJANGO_DEBUG       = "False"
    AUTH_TOKEN_TTL     = "7200"
    POSTGRES_NAME      = var.db_name
    POSTGRES_USER      = var.db_user
    DB_HOST            = var.db_host
    DB_PORT            = tostring(var.db_port)
    HOME               = "/tmp"
    XDG_CACHE_HOME     = "/tmp/.cache"
    XDG_CONFIG_HOME    = "/tmp/.config"
    XDG_DATA_HOME      = "/tmp/.local/share"
  }

  # Upstream's compose file runs these containers locked down the same way.
  hardening = [
    "Network=host",
    "ReadOnly=true",
    "DropCapability=all",
    "NoNewPrivileges=true",
    "Tmpfs=/tmp:rw,noexec,nosuid,nodev",
  ]

  # Attachments, the task queue and the OIDC signing key live here. U hands
  # the volume to the user the containers run as.
  data_volume = "ciso-assistant:/code/db:U"
}

# Facts give each host's memory. On a 2 GB host the backend ran the host out
# of memory; 4 GB leaves room.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = self.memory_mb >= var.min_memory_mb
      error_message = "Host ${each.key} has ${self.memory_mb} MiB of memory, under the ${var.min_memory_mb} MiB this circuit asks for. Set min_memory_mb lower to go ahead anyway."
    }
  }
}

# The Django secret key is generated on the host by the first apply and never
# passes through Conn3x, so it's in neither the plan nor state. The backend
# and the worker have to share it, and upstream's startup script only makes
# one for the backend. creates keeps it from ever being replaced.
circuit "keys" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "dir" {
    depends_on = [data.conn3x_host.facts]
    directory {
      path  = local.dir
      owner = "root"
      group = "root"
      mode  = "0700"
    }
  }

  step "generate" {
    command {
      command = <<-EOT
        set -eu
        umask 077
        cd ${local.dir}
        printf 'DJANGO_SECRET_KEY=%s\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > keys.env.new
        mv keys.env.new keys.env
      EOT
      creates = local.keys_file
    }
  }
}

# Three containers from upstream's images, each a Quadlet unit on the host's
# network, so they reach a PostgreSQL that listens only on localhost.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"

  depends_on = [conn3x_command.keys__generate]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  containers = {
    # Upstream's startup script binds gunicorn to every address, with no
    # setting to change it, and on the host's network that would put the API
    # outside the proxy. So the unit runs a copy with the bind on loopback.
    # If upstream rewrites that line, the grep fails and the service won't
    # start, rather than quietly listening everywhere.
    ciso-assistant-backend = {
      image   = local.backend_image
      volumes = [local.data_volume]
      environment = merge(local.backend_env, {
        PORT                   = tostring(var.backend_port)
        DJANGO_SUPERUSER_EMAIL = var.admin_email
      })
      extra = concat(local.hardening, [
        "User=1001:1001",
        "EnvironmentFile=${local.keys_file}",
        "PodmanArgs=--entrypoint=/bin/bash",
        "Exec=-c \"sed 's/--bind :/--bind 127.0.0.1:/' startup.sh > /tmp/startup.sh && grep -q -e '--bind 127.0.0.1:' /tmp/startup.sh && exec bash /tmp/startup.sh\"",
      ])
    }

    # Runs background tasks such as scheduled reminders and mail.
    ciso-assistant-huey = {
      image       = local.backend_image
      volumes     = [local.data_volume]
      environment = local.backend_env
      extra = concat(local.hardening, [
        "User=1001:1001",
        "EnvironmentFile=${local.keys_file}",
        "PodmanArgs=--entrypoint=/bin/sh",
        "Exec=-c \"python manage.py run_huey -w 2 --scheduler-interval 60\"",
      ])
    }

    # ORIGIN tells the server its public address outright, in place of
    # upstream's forwarded headers, which anyone reaching the port could set.
    ciso-assistant-frontend = {
      image = local.frontend_image
      environment = {
        HOST                           = var.listen_address
        PORT                           = tostring(var.port)
        ORIGIN                         = var.public_url
        PUBLIC_BACKEND_API_URL         = "http://127.0.0.1:${var.backend_port}/api"
        PUBLIC_BACKEND_API_EXPOSED_URL = "${var.public_url}/api"
      }
      extra = local.hardening
    }
  }
  secrets = {
    ciso-assistant-backend = merge(var.environment, {
      POSTGRES_PASSWORD         = var.db_password
      DJANGO_SUPERUSER_PASSWORD = var.admin_password
    })
    ciso-assistant-huey = merge(var.environment, {
      POSTGRES_PASSWORD = var.db_password
    })
  }
}

circuit "ciso_assistant" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # The backend migrates the database and stores its framework libraries
  # before it opens its port. That took over 15 minutes on a 2-vCPU host.
  step "backend_ready" {
    depends_on = [module.podman]
    wait_for {
      port    = var.backend_port
      timeout = "45m"
    }
  }

  step "frontend_ready" {
    wait_for {
      port    = var.port
      timeout = "5m"
    }
  }
}
