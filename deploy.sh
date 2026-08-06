#!/usr/bin/env bash
# Push ./Caddyfile to the server and reload Caddy.
#
# Safe to run repeatedly. The config is validated on the server BEFORE it
# replaces the live one, so a syntax error fails here instead of taking your
# sites down. Caddy reloads with zero downtime — connections are not dropped.
set -euo pipefail

cd "$(dirname "$0")"

USER_NAME="$(terraform output -raw admin_user 2>/dev/null || echo leo)"
HOST="$(terraform output -raw ipv4)"
TARGET="${USER_NAME}@${HOST}"

echo "==> Uploading Caddyfile to ${TARGET}"
rsync -q Caddyfile "${TARGET}:/tmp/Caddyfile"

echo "==> Validating on server"
ssh "${TARGET}" 'caddy validate --adapter caddyfile --config /tmp/Caddyfile' >/dev/null

echo "==> Installing and reloading"
ssh "${TARGET}" '
  sudo install -o root -g root -m 644 /tmp/Caddyfile /etc/caddy/Caddyfile &&
  sudo systemctl reload caddy &&
  rm -f /tmp/Caddyfile
'

echo "==> Done. Live config:"
ssh "${TARGET}" 'systemctl is-active caddy'
