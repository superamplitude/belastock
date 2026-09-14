#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo " BELA STOCK - DIAGNOSTICO ROOT NGINX"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

sudo -n /usr/local/sbin/belastock-vps-control nginx-diagnose

echo "ROOT_NGINX_DIAG=COMPLETE"
