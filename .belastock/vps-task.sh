#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
VALIDATOR="$ROOT/.belastock/validate-v22-runtime.mjs"

echo "============================================================"
echo " BELA STOCK 2.2 - PROVA FINAL END-TO-END"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && npm run check"

PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "2.2.0"

echo "===== DB / TENANT / PROVIDERS PROOF ====="
chmod o+r "$VALIDATOR"
sudo -n -u lojabelastock -H node "$VALIDATOR"

echo "===== PUBLIC / AUTH BOUNDARY PROOF ====="
check_code(){
  local expected="$1" url="$2" file="$3"
  local code
  code="$(curl -ksS --max-time 20 -o "$file" -w '%{http_code}' "$url" || true)"
  echo "$url -> $code"
  test "$code" = "$expected"
}

check_code 200 https://belastock.com.br/ /tmp/bs22-root.html
check_code 200 https://belastock.com.br/health /tmp/bs22-health.json
check_code 200 https://belastock.com.br/cliente /tmp/bs22-cliente.html
check_code 200 https://belastock.com.br/parceiro /tmp/bs22-parceiro.html
check_code 200 https://belastock.com.br/admin /tmp/bs22-admin.html
check_code 200 https://belastock.com.br/api/public/store /tmp/bs22-store.json
check_code 401 https://belastock.com.br/api/customer/panel /tmp/bs22-customer-unauth.json
check_code 401 https://belastock.com.br/api/partner/panel /tmp/bs22-partner-unauth.json
check_code 401 https://belastock.com.br/api/admin/payment-providers /tmp/bs22-payment-unauth.json
check_code 401 https://belastock.com.br/api/admin/shipping-providers /tmp/bs22-shipping-unauth.json

WWW_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://www.belastock.com.br/ || true)"
echo "PUBLIC_WWW_HTTP=$WWW_CODE"
test "$WWW_CODE" = "301"

grep -q '"version":"2.2.0"' /tmp/bs22-health.json
grep -q '"db":true' /tmp/bs22-health.json
grep -q 'Painel do Cliente' /tmp/bs22-cliente.html
grep -q 'Painel do Parceiro' /tmp/bs22-parceiro.html
grep -q 'belastock' /tmp/bs22-store.json

echo "===== NGINX CANONICAL UPSTREAM PROOF ====="
sudo -n "$CONTROL" nginx-diagnose > /tmp/bs22-nginx-proof.txt || true
VHOST_PROXY="$(awk '/===== VHOST CONTENT =====/{inside=1;next}/===== ACTIVE BELASTOCK CONFIG REFERENCES =====/{inside=0} inside && /proxy_pass http:\/\/127\.0\.0\.1:[0-9]+\//{print;exit}' /tmp/bs22-nginx-proof.txt | xargs)"
echo "VHOST_PROXY=$VHOST_PROXY"
test -n "$VHOST_PROXY"
echo "$VHOST_PROXY" | grep -q 'proxy_pass http://127.0.0.1:3210/'

cat /tmp/bs22-health.json
cat /tmp/bs22-store.json

echo "BELA_STOCK_22_MULTISTORE=100%_OK"
echo "BELA_STOCK_22_CUSTOMER_PANEL=100%_OK"
echo "BELA_STOCK_22_PARTNER_PANEL=100%_OK"
echo "BELA_STOCK_22_PAYMENTS_ARCHITECTURE=100%_OK"
echo "BELA_STOCK_22_SHIPPING_ARCHITECTURE=100%_OK"
echo "BELA_STOCK_22_SUPPLIER_GATEWAY=100%_OK"
echo "EXECUCAO_TOTAL_BELASTOCK_22=CONCLUIDA"
