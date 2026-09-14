#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo " BELA STOCK - LOCALIZAR VHOSTS ROOT x LOJA"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/3] Arquivos/symlinks relacionados"
find /etc/nginx -maxdepth 5 \( -type f -o -type l \) -iname '*belastock*' -print 2>/dev/null | sort || true

echo "[2/3] server_name encontrados"
grep -RnsE 'server_name[[:space:]]+.*(belastock\.com\.br|loja\.belastock\.com\.br)' /etc/nginx 2>/dev/null || true

echo "[3/3] Raizes e proxies proximos"
for f in $(grep -RslE 'server_name[[:space:]]+.*(belastock\.com\.br|loja\.belastock\.com\.br)' /etc/nginx 2>/dev/null || true); do
  echo "--- $f"
  grep -nE 'server_name|listen |root |proxy_pass|fastcgi_pass|ssl_certificate' "$f" 2>/dev/null || true
done

echo "VHOST_DISCOVERY=COMPLETE"
