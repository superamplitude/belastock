#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
CONTROL="/usr/local/sbin/belastock-vps-control"

echo "============================================================"
echo " BELA STOCK 2.1 - SUPPLIER GATEWAY / RECOVERY 502"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

CONTROL_OK=0
for attempt in {1..12}; do
  echo "[CONTROL] tentativa $attempt/12"
  sudo -n "$CONTROL" refresh-control
  if grep -q 'node_db_ok' "$CONTROL"; then
    CONTROL_OK=1
    echo "[CONTROL] revisao MYSQL2 confirmada"
    break
  fi
  echo "[CONTROL] CDN ainda entregou revisao anterior; aguardando 20s"
  sleep 20
done
test "$CONTROL_OK" = "1"

sudo -n "$CONTROL" backup-site
chmod o+rx "$ROOT" "$ROOT/deploy" "$ROOT/deploy/runtime" "$ROOT/deploy/runtime/supplier-gateway" 2>/dev/null || true
find "$ROOT/deploy/runtime/supplier-gateway" -type d -exec chmod o+rx {} +
find "$ROOT/deploy/runtime/supplier-gateway" -type f -exec chmod o+r {} +
chmod o+rx "$ROOT/deploy/APPLY_SUPPLIER_GATEWAY_V21.sh"

sudo -n -u lojabelastock -H bash "$ROOT/deploy/APPLY_SUPPLIER_GATEWAY_V21.sh"
sudo -n "$CONTROL" runtime-repair

echo "===== VALIDACAO FINAL ====="
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health

PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "2.1.0"

HEALTH_FILE="$(mktemp)"
HEALTH_CODE="$(curl -ksS --resolve belastock.com.br:443:127.0.0.1 -o "$HEALTH_FILE" -w '%{http_code}' 'https://belastock.com.br/health')"
echo "HEALTH_HTTP=$HEALTH_CODE"
cat "$HEALTH_FILE"
grep -q '"version":"2.1.0"' "$HEALTH_FILE"
test "$HEALTH_CODE" = "200"
rm -f "$HEALTH_FILE"

ADAPTERS_CODE="$(curl -ksS --resolve belastock.com.br:443:127.0.0.1 -o /tmp/bs-adapters-unauth.json -w '%{http_code}' 'https://belastock.com.br/api/admin/supplier-adapters')"
echo "ADMIN_ADAPTERS_UNAUTH_HTTP=$ADAPTERS_CODE"
cat /tmp/bs-adapters-unauth.json || true
test "$ADAPTERS_CODE" = "401"

grep -q 'Simulador / Pré-importação' "$SITE/public/admin.html"
grep -q "app.post('/api/admin/suppliers/:id/simulate'" "$SITE/src/server.mjs"
grep -q 'supplier_import_profiles' "$SITE/migrations/002_supplier_gateway.sql"

echo "SUPPLIER_GATEWAY_V21=100%_OK"
