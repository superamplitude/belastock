#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK 3.2 - CORRECAO FINAL HEALTH / SPLIT"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/6] Aplicando correção idempotente do health e do roteamento host-aware"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/APPLY_PORTAL_LOJA_V32.sh"

echo "[2/6] Reiniciando Node"
sudo -n /usr/local/sbin/belastock-vps-control pm2-restart

echo "[3/6] Provando health com query string antes da troca do vhost"
LOCAL_Q="$(curl -sS --max-time 15 -H 'Host: loja.belastock.com.br' -o /tmp/bs-health-query.json -w '%{http_code}' "http://127.0.0.1:3210/health?split=proof-$(date +%s)" || true)"
echo "LOCAL_LOJA_HEALTH_QUERY_HTTP=$LOCAL_Q"
cat /tmp/bs-health-query.json || true
test "$LOCAL_Q" = 200

echo "[4/6] Atualizando controlador e migrando vhost loja para Node"
sudo -n /usr/local/sbin/belastock-vps-control refresh-control || true
sudo -n /usr/local/sbin/belastock-vps-control apply-loja-proxy

echo "[5/6] Validacao publica independente"
ROOT_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-root-final.html -w '%{http_code}' "https://belastock.com.br/?v32-healthfix=$(date +%s)" || true)"
LOJA_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-final.html -w '%{http_code}' "https://loja.belastock.com.br/?v32-healthfix=$(date +%s)" || true)"
HEALTH_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-health-public.json -w '%{http_code}' "https://loja.belastock.com.br/health?proof=$(date +%s)" || true)"
API_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-api.json -w '%{http_code}' "https://loja.belastock.com.br/api/public/store?v32-healthfix=$(date +%s)" || true)"
echo "ROOT_PUBLIC_HTTP=$ROOT_CODE"
echo "LOJA_PUBLIC_HTTP=$LOJA_CODE"
echo "LOJA_HEALTH_PUBLIC_HTTP=$HEALTH_CODE"
echo "LOJA_STORE_API_HTTP=$API_CODE"
test "$ROOT_CODE" = 200
test "$LOJA_CODE" = 200
test "$HEALTH_CODE" = 200
test "$API_CODE" = 200
grep -q 'Um mega portal' /tmp/bs-root-final.html
grep -q 'Departamentos Bela Stock' /tmp/bs-root-final.html
grep -q 'hero-slider' /tmp/bs-loja-final.html
grep -q 'VISTA SUA MELHOR' /tmp/bs-loja-final.html
grep -q '"code":"belastock"' /tmp/bs-loja-api.json
if grep -Eqi 'wp-content|wp-includes|wordpress' /tmp/bs-loja-final.html; then echo '[ERRO] WordPress ainda presente na loja publica' >&2; exit 1; fi

echo "[6/6] Status final"
sudo -n /usr/local/sbin/belastock-vps-control status

echo "LOJA_WORDPRESS_MARKERS=0"
echo "ROOT_BELASTOCK=PORTAL_MULTICANAL_OK"
echo "LOJA_BELASTOCK=STOREFRONT_NODE_OK"
echo "LOJA_BELASTOCK_WORDPRESS=REMOVIDO_DO_ROTEAMENTO_PUBLICO"
echo "BELA_STOCK_V32_DOMAIN_SPLIT=100%_OK"
