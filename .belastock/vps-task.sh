#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK 3.3 - LAYOUT PUBLICO RC14 + LOJA NATIVA"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/7] Garantindo split Portal/Loja e dominio loja no tenant raiz"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/APPLY_PORTAL_LOJA_V32.sh"

echo "[2/7] Aplicando layout aprovado RC14 na loja Node"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/APPLY_LOJA_VISUAL_RC14_V33.sh"

echo "[3/7] Reiniciando runtime Node"
sudo -n /usr/local/sbin/belastock-vps-control pm2-restart

echo "[4/7] Garantindo vhost da loja no runtime Node"
sudo -n /usr/local/sbin/belastock-vps-control refresh-control || true
sudo -n /usr/local/sbin/belastock-vps-control apply-loja-proxy

echo "[5/7] Validacao publica visual e funcional"
ROOT_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-root-v33.html -w '%{http_code}' "https://belastock.com.br/?v33=$(date +%s)" || true)"
LOJA_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-v33.html -w '%{http_code}' "https://loja.belastock.com.br/?v33=$(date +%s)" || true)"
HEALTH_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-health-v33.json -w '%{http_code}' "https://loja.belastock.com.br/health?v33=$(date +%s)" || true)"
STORE_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-store-v33.json -w '%{http_code}' "https://loja.belastock.com.br/api/public/store?v33=$(date +%s)" || true)"
PRODUCTS_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-products-v33.json -w '%{http_code}' "https://loja.belastock.com.br/api/public/products?limit=5&v33=$(date +%s)" || true)"
echo "ROOT_PUBLIC_HTTP=$ROOT_CODE"
echo "LOJA_PUBLIC_HTTP=$LOJA_CODE"
echo "LOJA_HEALTH_HTTP=$HEALTH_CODE"
echo "LOJA_STORE_API_HTTP=$STORE_CODE"
echo "LOJA_PRODUCTS_API_HTTP=$PRODUCTS_CODE"
test "$ROOT_CODE" = 200
test "$LOJA_CODE" = 200
test "$HEALTH_CODE" = 200
test "$STORE_CODE" = 200
test "$PRODUCTS_CODE" = 200

grep -q 'Um mega portal' /tmp/bs-root-v33.html
grep -q 'Departamentos Bela Stock' /tmp/bs-root-v33.html
grep -q 'Um mega portal' /tmp/bs-loja-v33.html
grep -q 'Muitos produtos' /tmp/bs-loja-v33.html
grep -q 'Departamentos Bela Stock' /tmp/bs-loja-v33.html
grep -q 'id="products"' /tmp/bs-loja-v33.html
grep -q 'id="cart-open"' /tmp/bs-loja-v33.html
grep -q 'id="cart-drawer"' /tmp/bs-loja-v33.html
if grep -q 'VISTA SUA MELHOR VERSÃO' /tmp/bs-loja-v33.html; then echo '[ERRO] Layout antigo ainda publicado' >&2; exit 1; fi
if grep -Eqi 'wp-content|wp-includes|wordpress' /tmp/bs-loja-v33.html; then echo '[ERRO] WordPress detectado na loja publica' >&2; exit 1; fi

echo "[6/7] Validacao do estado da aplicacao"
cd "$SITE"
test "$(node -p "require('./package.json').version")" = "3.3.0"
node --check src/server.mjs
node --check public/storefront.js
sudo -n /usr/local/sbin/belastock-vps-control health

echo "[7/7] Status final"
sudo -n /usr/local/sbin/belastock-vps-control status

echo "LOJA_LAYOUT_ANTIGO=REMOVIDO"
echo "LOJA_LAYOUT_RC14=PUBLICADO"
echo "LOJA_CATALOGO_CARRINHO_CHECKOUT=PRESERVADOS"
echo "BELA_STOCK_V33=100%_OK"
