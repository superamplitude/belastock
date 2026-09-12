#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"

printf '============================================================\n'
printf ' BELA STOCK VPS TASK - INVENTARIO SEGURO\n'
printf '============================================================\n'
echo "HOST=$(hostname)"
echo "USER=$(id -un)"
echo "DATE=$(date -Is)"

sudo -n /usr/local/sbin/belastock-vps-control inventory
sudo -n /usr/local/sbin/belastock-vps-control db-test || true
sudo -n /usr/local/sbin/belastock-vps-control status || true

if [ -d "$SITE" ]; then
  echo "SITE_EXISTS=1"
else
  echo "SITE_EXISTS=0"
fi

printf '============================================================\n'
printf ' BELA STOCK VPS TASK CONCLUIDA\n'
printf '============================================================\n'
