# Local example

Applies circuit-ciso-assistant to a throwaway Rocky Linux 10 container with systemd, with [circuit-postgres](https://github.com/conn3xorg/circuit-postgres) on the same host. You need Conn3x, Podman, and about 4 GB of memory free for the container, plus about 4 GB of disk for the images.

CISO Assistant runs under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The first apply takes a few minutes: it installs PostgreSQL and Podman, pulls the images, and waits while CISO Assistant sets up its database and stores its framework libraries. The second plan says `No changes.` The example's passwords are defaults in `main.tf`, which you'd never keep on a real host.

To see it work, run the same check CI runs. It logs in through the API and through the web interface, makes sure a wrong password is refused, loads the SOC 2, ISO 27001 and HIPAA libraries, and checks that both ports are on loopback:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  podman exec -i ciso-assistant-backend python - < check.py
```

The administrator signs in as `admin@example.com` with `audit-binder-lantern`.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
