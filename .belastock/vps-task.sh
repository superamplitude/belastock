#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"

echo "============================================================"
echo " BELA STOCK - DIAGNOSTICO NGINX 502"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

echo "===== LOCAL APP ====="
curl -sS -i --max-time 10 http://127.0.0.1:3210/health || true

echo "===== PORT 3210 ====="
ss -lntp 2>/dev/null | grep ':3210' || true

echo "===== VHOST TARGET ====="
readlink -f "$VHOST" 2>/dev/null || true
ls -l "$VHOST" 2>/dev/null || true

echo "===== VHOST CONTENT ====="
sed -n '1,320p' "$VHOST" 2>/dev/null || true

echo "===== ALL BELASTOCK REFERENCES ====="
grep -RniE 'server_name[[:space:]].*belastock\.com\.br|proxy_pass[[:space:]]+http' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true

echo "===== ORIGIN HEALTH ====="
curl -ksS -i --resolve belastock.com.br:443:127.0.0.1 --max-time 10 https://belastock.com.br/health || true

echo "===== NGINX ERROR TAIL ====="
tail -n 80 /var/log/nginx/error.log 2>/dev/null || true

echo "NGINX_502_DIAGNOSTIC=COMPLETE"
