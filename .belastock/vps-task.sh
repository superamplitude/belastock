#!/usr/bin/env bash
set -Eeuo pipefail

CONTROL="/usr/local/sbin/belastock-vps-control"

echo "============================================================"
echo " BELA STOCK - ROOT NGINX DIAGNOSTIC"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

for attempt in {1..12}; do
  sudo -n "$CONTROL" refresh-control
  if grep -q 'BELASTOCK_NGINX_DIAG_V1' "$CONTROL"; then
    echo "CONTROL_NGINX_DIAG=READY"
    sudo -n "$CONTROL" nginx-diagnose
    exit 0
  fi
  echo "CONTROL_NGINX_DIAG=WAITING attempt=$attempt"
  sleep 20
done

echo "CONTROL_NGINX_DIAG=TIMEOUT"
exit 1
