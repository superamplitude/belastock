#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"

echo "============================================================"
echo " BELA STOCK 2.1 - SUPPLIER GATEWAY / EXECUCAO TOTAL"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

# O controlador root e a unica porta administrativa do runner.
sudo -n /usr/local/sbin/belastock-vps-control refresh-control
sudo -n /usr/local/sbin/belastock-vps-control backup-site

# O checkout pertence ao runner; libera apenas leitura/execucao deste payload
# para o usuario dono do Bela Stock.
chmod o+rx "$ROOT" "$ROOT/deploy" "$ROOT/deploy/runtime" "$ROOT/deploy/runtime/supplier-gateway" 2>/dev/null || true
find "$ROOT/deploy/runtime/supplier-gateway" -type d -exec chmod o+rx {} +
find "$ROOT/deploy/runtime/supplier-gateway" -type f -exec chmod o+r {} +
chmod o+rx "$ROOT/deploy/APPLY_SUPPLIER_GATEWAY_V21.sh"

sudo -n -u lojabelastock -H bash "$ROOT/deploy/APPLY_SUPPLIER_GATEWAY_V21.sh"

# Repara runtime sem tocar no PM2 root de outros projetos, preserva banco antes
# de qualquer ajuste de credencial e aplica migrations idempotentes.
sudo -n /usr/local/sbin/belastock-vps-control runtime-repair

echo "===== VALIDACAO FINAL ====="
sudo -n /usr/local/sbin/belastock-vps-control db-test
sudo -n /usr/local/sbin/belastock-vps-control health

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

# Sem token, rota nova deve existir e negar acesso (401), nunca 404.
ADAPTERS_CODE="$(curl -ksS --resolve belastock.com.br:443:127.0.0.1 -o /tmp/bs-adapters-unauth.json -w '%{http_code}' 'https://belastock.com.br/api/admin/supplier-adapters')"
echo "ADMIN_ADAPTERS_UNAUTH_HTTP=$ADAPTERS_CODE"
cat /tmp/bs-adapters-unauth.json || true
test "$ADAPTERS_CODE" = "401"

# Prova estrutural do simulador e das tabelas novas.
grep -q 'Simulador / Pré-importação' "$SITE/public/admin.html"
grep -q "app.post('/api/admin/suppliers/:id/simulate'" "$SITE/src/server.mjs"
grep -q 'supplier_import_profiles' "$SITE/migrations/002_supplier_gateway.sql"

echo "SUPPLIER_GATEWAY_V21=100%_OK"
