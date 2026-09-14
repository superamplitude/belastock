#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK 3.2 - ROOT PORTAL / LOJA NODE"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/7] Backup completo antes da alteracao"
sudo -n /usr/local/sbin/belastock-vps-control backup-site

echo "[2/7] Aplicando codigo host-aware e portal raiz"
test -f "$REPO_ROOT/deploy/APPLY_PORTAL_LOJA_V32.sh"
test -f "$REPO_ROOT/deploy/runtime/portal-loja-v32/public/portal.html"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/APPLY_PORTAL_LOJA_V32.sh"

echo "[3/7] Reiniciando Node com health estavel"
sudo -n /usr/local/sbin/belastock-vps-control pm2-restart

echo "[4/7] Atualizando controlador root auditavel"
sudo -n /usr/local/sbin/belastock-vps-control refresh-control

echo "[5/7] Migrando SOMENTE o vhost loja.belastock.com.br de WordPress para Node"
sudo -n /usr/local/sbin/belastock-vps-control apply-loja-proxy

echo "[6/7] Validacao publica independente"
ROOT_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-root-final.html -w '%{http_code}' "https://belastock.com.br/?v32=$(date +%s)" || true)"
LOJA_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-final.html -w '%{http_code}' "https://loja.belastock.com.br/?v32=$(date +%s)" || true)"
API_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-api.json -w '%{http_code}' "https://loja.belastock.com.br/api/public/store?v32=$(date +%s)" || true)"
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

echo "[7/7] Health/status final"
sudo -n /usr/local/sbin/belastock-vps-control health
sudo -n /usr/local/sbin/belastock-vps-control status

echo "ROOT_BELASTOCK=PORTAL_MULTICANAL_OK"
echo "LOJA_BELASTOCK=STOREFRONT_NODE_OK"
echo "WORDPRESS_LOJA_VHOST=DESATIVADO_COM_BACKUP"
echo "BELA_STOCK_V32_DOMAIN_SPLIT=100%_OK"
