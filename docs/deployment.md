# Deployment

The stack runs on one Ubuntu 24.04 server. Images are built on your workstation and copied over SSH, so the server never builds anything.

Examples on this page use these placeholders. Replace them with your own values.

| Placeholder | Meaning |
|---|---|
| `shop.example.com` | Your domain. The store is served here. |
| `203.0.113.10` | The server's public IPv4 address |
| `22` | The server's SSH port |
| `admin` | Your own login on the server, with sudo |
| `you@example.com` | Your email, for Let's Encrypt |

Everything on the server lives in `/opt/medusa`, owned by the `deploy` user. Settings and secrets are in `/opt/medusa/.env` (mode 600), which is never committed.

## First deploy

### What you need

- A VPS with Ubuntu 24.04, at least 2 GB RAM and 30 GB disk, reachable as root or a sudo user over SSH
- A domain where you can edit DNS records
- A workstation with Git, Docker, `make` and OpenSSH. On Windows, use WSL.

### 1. Clone the repository (workstation)

```bash
git clone https://github.com/4slava/medusa-deploy.git
cd medusa-deploy
```

All workstation commands below run from this folder.

### 2. Point DNS at the server

Create these records at your DNS provider:

| Name | Type | Value |
|---|---|---|
| `shop.example.com` | A | `203.0.113.10` |
| `www.shop.example.com` | A | `203.0.113.10` |
| `api.shop.example.com` | A | `203.0.113.10` |

Use the bare domain for the store. `www.` redirects to it, and `api.` serves the API and admin. Remove any `AAAA` records for these names unless they point at this server, because Let's Encrypt prefers IPv6.

Check from the workstation. All three names must return the server's IP:

```bash
getent hosts shop.example.com www.shop.example.com api.shop.example.com
```

### 3. Create SSH keys (workstation)

Use two keys: one for your own admin login and one for deploys. Skip the first if you already have a key you use for servers.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/shop_admin_key -C shop-admin
ssh-keygen -t ed25519 -f ~/.ssh/shop_deploy_key -C shop-deploy
```

Give both a passphrase. Add both hosts to `~/.ssh/config`:

```
Host shop-admin
    HostName 203.0.113.10
    Port 22
    User admin
    IdentityFile ~/.ssh/shop_admin_key

Host shop-deploy
    HostName 203.0.113.10
    Port 22
    User deploy
    IdentityFile ~/.ssh/shop_deploy_key
```

### 4. Create your admin user (server)

Skip this if the provider already gave you a sudo user with key login. Otherwise log in as root with the provider's password:

```bash
ssh root@203.0.113.10
adduser admin
usermod -aG sudo admin
exit
```

From the workstation, install your admin key and test it:

```bash
ssh-copy-id -i ~/.ssh/shop_admin_key.pub admin@203.0.113.10
ssh shop-admin sudo whoami
```

The last command must print `root`. Do not continue until key login works, because the next step turns off password and root login.

### 5. Prepare the server (server)

Copy the setup script, keep a second SSH session open in case something goes wrong, and run it:

```bash
scp infra/scripts/server-setup.sh shop-admin:
ssh -t shop-admin "sudo SSH_PORT=22 ADMIN_USER=admin DEPLOY_PUBKEY='$(cat ~/.ssh/shop_deploy_key.pub)' bash server-setup.sh"
```

`SSH_PORT` must be the port SSH already listens on. The script refuses to run if nothing listens there, or if `admin` has no SSH key.

It installs Docker, turns on the `ufw` firewall for SSH, 80 and 443, hardens SSH, adds fail2ban and 4 GB of swap, and creates the `deploy` user with your deploy key. `deploy` has no sudo, but it can run Docker, which is equivalent to root on this server.

Reboot if the script says so:

```bash
ssh -t shop-admin 'test -f /var/run/reboot-required && sudo reboot'
```

If your provider also has a firewall, allow TCP 80 from everywhere. Let's Encrypt needs it to issue and renew certificates. You can limit 443 to your own IP while testing.

### 6. Load the deploy key (workstation)

The release scripts never prompt, so a passphrase-protected key must be loaded into `ssh-agent` first. Do this once per terminal:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/shop_deploy_key
ssh -o BatchMode=yes shop-deploy whoami
export DEPLOY_TARGET=shop-deploy
```

The test must print `deploy` without asking for anything.

### 7. Configure the server (workstation and server)

Copy the compose file and scripts to the server:

```bash
make sync
```

Then, on the server, create `.env` with random secrets and get the certificate. The staging run checks DNS and ports without using up Let's Encrypt's rate limits:

```bash
ssh shop-deploy
cd /opt/medusa
DOMAIN=shop.example.com ACME_EMAIL=you@example.com infra/scripts/init-env.sh
STAGING=1 infra/scripts/init-tls.sh
docker compose run --rm --no-deps --entrypoint certbot certbot \
  delete --non-interactive --cert-name shop.example.com
infra/scripts/init-tls.sh
exit
```

### 8. Release (workstation)

```bash
make release
```

A first release builds the backend, starts it so the database and publishable key are created, then builds the storefront with that key. It ends with `Deployed medusa-backend:... + medusa-storefront:...`.

### 9. Finish (server)

```bash
ssh shop-deploy
cd /opt/medusa
docker compose run --rm --no-deps medusa-server \
  node_modules/.bin/medusa user -e you@example.com -p 'long-random-password'
(crontab -l 2>/dev/null; echo '17 3 * * * cd /opt/medusa && infra/scripts/backup.sh >> /var/backups/medusa/backup.log 2>&1') | crontab -
docker compose run --rm --no-deps --entrypoint certbot certbot renew --dry-run
```

This creates your admin login, schedules a nightly backup, and checks that certificate renewal will work.

Open these to check:

- `https://shop.example.com`: the store
- `https://www.shop.example.com`: redirects to the store
- `https://api.shop.example.com/app`: the admin

## Releases

From the workstation, with the deploy key loaded and `DEPLOY_TARGET` set:

```bash
make release
```

`make release` builds locally, copies the images over SSH, and runs `infra/scripts/deploy.sh` on the server. That script takes a backup, switches images, waits for health checks, and restores the previous images if they fail.

### Automated deploys

Pushing a tag such as `v1.2.3` runs `.github/workflows/cd-production.yml`. Create a separate deploy key for it without a passphrase, because CI cannot type one, and add its public key to `/home/deploy/.ssh/authorized_keys`. Then add these to the `production` GitHub environment:

| Type | Name | Value |
|---|---|---|
| Secret | `VPS_SSH_PRIVATE_KEY` | The CI deploy key's private key |
| Secret | `VPS_KNOWN_HOSTS` | Output of `ssh-keyscan -p 22 203.0.113.10` |
| Variable | `VPS_HOST` | `203.0.113.10` |
| Variable | `VPS_PORT` | `22` |
| Variable | `DOMAIN` | `shop.example.com` |
| Variable | `PUBLISHABLE_KEY` | Output of `infra/scripts/publishable-key.sh` on the server |

## Changing the domain

The domain is set in one place, `DOMAIN` in `/opt/medusa/.env`. The storefront image also contains it, so a change needs a new certificate and a release. Below, `new.example.com` is the new domain and `old.example.com` the current one.

1. **DNS.** Point `new.example.com`, `www.new.example.com` and `api.new.example.com` at the server, as in step 2 of the first deploy. Wait until `getent hosts` returns the server's IP for all three.

2. **Certificate.** Request it through the running nginx. The site keeps working, and nothing changes if this fails. Do not use `init-tls.sh` here, because it needs port 80 free.

   ```bash
   ssh shop-deploy
   cd /opt/medusa
   docker compose run --rm --no-deps --entrypoint certbot certbot certonly \
     --webroot -w /var/www/certbot --non-interactive \
     --cert-name new.example.com \
     -d new.example.com -d www.new.example.com -d api.new.example.com
   ```

3. **Switch.** Change `DOMAIN`, then release from the workstation. Do not restart the stack between these two steps.

   ```bash
   sed -i 's|^DOMAIN=.*|DOMAIN=new.example.com|' .env
   exit
   make release
   ```

   The site is briefly down while it restarts, and the old domain stops working.

4. **Clean up.** Delete the old certificate so certbot stops renewing it, and check renewal for the new one:

   ```bash
   ssh shop-deploy
   cd /opt/medusa
   docker compose run --rm --no-deps --entrypoint certbot certbot \
     delete --non-interactive --cert-name old.example.com
   docker compose run --rm --no-deps --entrypoint certbot certbot renew --dry-run
   ```

If the release fails, it restores the previous images but not `DOMAIN`. Set `DOMAIN` back to `old.example.com` and run `docker compose up -d`.

After the change:

- Files uploaded to the local volume keep their old URLs in the database, and those URLs stop working. Upload them again.
- Admin users have to log in again.
- If you use automated deploys, update the `DOMAIN` variable in GitHub.
- Other domains you own, such as a country domain, can redirect to the new one from your registrar's panel. Point the redirect at `https://new.example.com/`.

## Rollback

A failed release rolls back by itself. To go back by hand:

```bash
cd /opt/medusa
docker image ls
infra/scripts/deploy.sh medusa-backend:<tag> medusa-storefront:<tag>
```

Rollback changes images only and does not reverse migrations. If a migration caused the problem, restore the backup taken just before that deploy.

## Backups

`backup.sh` writes database and uploads archives to `/var/backups/medusa` and keeps 14 days.

**These backups are on the same disk as the data.** Set `BACKUP_REMOTE` to an rsync target (it needs `rsync` on the server) to protect against losing the server.

```bash
infra/scripts/restore.sh /var/backups/medusa/db-<stamp>.dump --check   # safe test
infra/scripts/restore.sh /var/backups/medusa/db-<stamp>.dump           # replaces live data
```

## Troubleshooting

```bash
docker compose ps -a
docker compose logs -f --tail 100 medusa-server
docker stats --no-stream
```

| Symptom | Check |
|---|---|
| `Permission denied (publickey)` on release | The deploy key is not loaded: run `ssh-add` in the same terminal |
| Certificate request fails | All names resolve to the server, and port 80 is open to everyone, including in the provider's firewall |
| `medusa-server` waits forever | `docker compose logs migrate` |
| Storefront shows no products | The publishable key built into the image still exists and has a sales channel |
| Admin login fails | `ADMIN_CORS` and `AUTH_CORS` in `docker-compose.yml` match the URL in use |
| HTTP 429 | Rate limits in `infra/docker/nginx/nginx.conf` |
| Containers killed | `docker stats`, `dmesg | grep -i oom`, memory limits in `docker-compose.yml` |
