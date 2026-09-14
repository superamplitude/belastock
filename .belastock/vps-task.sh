#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"

echo "============================================================"
echo " BELA STOCK 3.2 - FECHAMENTO ROOT PORTAL / LOJA NODE"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/5] Atualizando controlador corrigido"
sudo -n /usr/local/sbin/belastock-vps-control refresh-control

echo "[2/5] Reaplicando vhost da loja para Node"
sudo -n /usr/local/sbin/belastock-vps-control apply-loja-proxy

echo "[3/5] Validacao publica independente"
ROOT_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-root-final.html -w '%{http_code}' "https://belastock.com.br/?v32-final=$(date +%s)" || true)"
LOJA_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-final.html -w '%{http_code}' "https://loja.belastock.com.br/?v32-final=$(date +%s)" || true)"
API_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-api.json -w '%{http_code}' "https://loja.belastock.com.br/api/public/store?v32-final=$(date +%s)" || true)"
echo "ROOT_PUBLIC_HTTP=$ROOT_CODE"
echo "LOJA_PUBLIC_HTTP=$LOJA_CODE"
echo "LOJA_STORE_API_HTTP=$API_CODE"
test "$ROOT_CODE" = 200
test "$LOJA_CODE" = 200
test "$API_CODE" = 200
grep -q 'Um mega portal' /tmp/bs-root-final.html
grep -q 'Departamentos Bela Stock' /tmp/bs-root-final.html
grep -q 'hero-slider' /tmp/bs-loja-final.html
grep -q 'VISTA SUA MELHOR' /tmp/bs-loja-final.html
grep -q '"code":"belastock"' /tmp/bs-loja-api.json

echo "[4/5] Conferindo ausencia do WordPress na resposta publica da loja"
if grep -Eqi 'wp-content|wp-includes|wordpress' /tmp/bs-loja-final.html; then
  echo "[ERRO] Loja publica ainda contem marcadores WordPress" >&2
  exit 1
fi
echo "LOJA_WORDPRESS_MARKERS=0"

echo "[5/5] Status final"
sudo -n /usr/local/sbin/belastock-vps-control status

echo "ROOT_BELASTOCK=PORTAL_MULTICANAL_OK"
echo "LOJA_BELASTOCK=STOREFRONT_NODE_OK"
echo "LOJA_BELASTOCK_WORDPRESS=REMOVIDO_DO_ROTEAMENTO_PUBLICO"
echo "BELA_STOCK_V32_DOMAIN_SPLIT=100%_OK"
