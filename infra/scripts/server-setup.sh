#!/usr/bin/env bash
# Prepares a fresh Ubuntu 24.04 VPS. Safe to re-run. Run as root.
#   sudo SSH_PORT=22 ADMIN_USER=admin DEPLOY_PUBKEY="ssh-ed25519 AAAA..." bash server-setup.sh
#
# SSH_PORT must be the port sshd already listens on: this script opens it in
# the firewall but does not move sshd. DEPLOY_PUBKEY is optional and is added
# to the deploy user's authorized_keys.
#
# Keep a second SSH session open while running this for the first time.
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
ADMIN_USER="${ADMIN_USER:?set ADMIN_USER to your sudo login}"
export DEBIAN_FRONTEND=noninteractive

# Refuse to run where the hardening below would lock everyone out
ss -Hltn "sport = :${SSH_PORT}" | grep -q . ||
  { echo "Nothing listens on port ${SSH_PORT}. Set SSH_PORT to the current sshd port." >&2; exit 1; }
admin_home="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
[ -n "$admin_home" ] && [ -s "$admin_home/.ssh/authorized_keys" ] ||
  { echo "${ADMIN_USER} needs a key in ~/.ssh/authorized_keys before password login is disabled." >&2; exit 1; }

apt-get update -qq
apt-get -y -qq -o Dpkg::Options::=--force-confold upgrade
apt-get -y -qq install ca-certificates curl fail2ban ufw

# Firewall. Docker publishes 80/443 itself and bypasses ufw, so the compose
# file must never publish anything else.
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment ssh
ufw allow 80/tcp comment http
ufw allow 443/tcp comment https
ufw --force enable

cat > /etc/ssh/sshd_config.d/10-hardening.conf <<CONF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 4
LoginGraceTime 30
AllowUsers ${ADMIN_USER} deploy
CONF
sshd -t
systemctl reload ssh

cat > /etc/fail2ban/jail.d/sshd.local <<CONF
[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
CONF
systemctl enable fail2ban
systemctl restart fail2ban

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get -y -qq install docker-ce docker-ce-cli containerd.io docker-compose-plugin

cat > /etc/docker/daemon.json <<'CONF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true
}
CONF
systemctl enable docker
systemctl restart docker

if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
cat > /etc/sysctl.d/90-medusa.conf <<'CONF'
vm.swappiness=10
vm.overcommit_memory=1
net.core.somaxconn=1024
CONF
sysctl --system >/dev/null

# Deploy user: no sudo, but note that the docker group is root-equivalent.
id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -d -m 750 -o deploy -g deploy /opt/medusa /var/backups/medusa
if [ -n "${DEPLOY_PUBKEY:-}" ]; then
  keys=/home/deploy/.ssh/authorized_keys
  touch "$keys"
  grep -qxF "$DEPLOY_PUBKEY" "$keys" || echo "$DEPLOY_PUBKEY" >> "$keys"
  chown deploy:deploy "$keys"
  chmod 600 "$keys"
fi

echo "Done. Reboot if /var/run/reboot-required exists."
