#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
AUDIT="$ROOT/.belastock/audit-v3.mjs"

echo "============================================================"
echo " BELA STOCK - AUDITORIA DE CONCLUSAO 100%"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
chmod o+r "$AUDIT"
sudo -n -u lojabelastock -H node "$AUDIT"
echo "FULL_AUDIT_BELASTOCK=CONCLUIDA"
