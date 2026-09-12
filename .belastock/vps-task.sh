#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo " BELA STOCK VPS TASK - DIAGNOSTICO PM2"
echo "============================================================"
echo "HOST=$(hostname)"
echo "USER=$(id -un)"
echo "DATE=$(date -Is)"

echo "--- PM2 ROOT PATH ---"
command -v pm2 || true
ls -l /usr/local/bin/pm2 2>/dev/null || true
readlink -f /usr/local/bin/pm2 2>/dev/null || true
namei -l /usr/local/bin/pm2 2>/dev/null || true

echo "--- APP USER ACCESS ---"
sudo -n -u lojabelastock bash -lc 'id; command -v node || true; command -v npm || true; command -v pm2 || true; ls -l /usr/local/bin/pm2 2>/dev/null || true; readlink -f /usr/local/bin/pm2 2>/dev/null || true; /usr/local/bin/pm2 -v 2>&1 || true'

echo "--- NODE/NPM GLOBALS ---"
npm root -g 2>/dev/null || true
npm prefix -g 2>/dev/null || true
ls -ld /usr/local/lib/node_modules /usr/local/lib/node_modules/pm2 /usr/local/lib/node_modules/pm2/bin 2>/dev/null || true
ls -l /usr/local/lib/node_modules/pm2/bin/pm2 2>/dev/null || true

echo "--- STATUS CONTROL ---"
sudo -n /usr/local/sbin/belastock-vps-control status || true

echo "============================================================"
echo " DIAGNOSTICO PM2 CONCLUIDO"
echo "============================================================"
