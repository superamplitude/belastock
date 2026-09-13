#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
DB_AUDIT="$ROOT/.belastock/final-adversarial-audit.mjs"

echo "============================================================"
echo " BELA STOCK 3.0 - AUDITORIA DE PRODUCAO REUTILIZAVEL"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
sudo -n "$CONTROL" status
systemctl is-active --quiet pm2-lojabelastock
systemctl is-enabled --quiet pm2-lojabelastock
sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && npm run check && npm audit --omit=dev --audit-level=high"
chmod o+r "$DB_AUDIT"
sudo -n -u lojabelastock -H node "$DB_AUDIT"

for url in / /health /admin /cliente /parceiro /api/public/store /api/public/products; do
  code="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' "https://belastock.com.br${url}" || true)"
  echo "PUBLIC ${url}=$code"
  test "$code" = 200
done

ADMIN_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://belastock.com.br/api/admin/completion || true)"
CUSTOMER_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://belastock.com.br/api/customer/panel || true)"
PARTNER_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://belastock.com.br/api/partner/panel || true)"
echo "PRIVATE admin=$ADMIN_CODE customer=$CUSTOMER_CODE partner=$PARTNER_CODE"
test "$ADMIN_CODE" = 401
test "$CUSTOMER_CODE" = 401
test "$PARTNER_CODE" = 401

echo "BELA_STOCK_REUSABLE_PRODUCTION_AUDIT=100%_OK"
