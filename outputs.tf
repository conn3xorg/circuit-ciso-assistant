output "services" {
  description = "The systemd services that run CISO Assistant on each host."
  value       = ["ciso-assistant-backend.service", "ciso-assistant-huey.service", "ciso-assistant-frontend.service"]
}

output "images" {
  description = "The images the hosts run, by service."
  value = {
    ciso-assistant-backend  = local.backend_image
    ciso-assistant-huey     = local.backend_image
    ciso-assistant-frontend = local.frontend_image
  }
}

output "keys_file" {
  description = "File on each host holding the generated DJANGO_SECRET_KEY. Back it up with the database."
  value       = local.keys_file
}
