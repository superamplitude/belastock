#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK - DEPLOY HOME HERO V3.1"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

test -d "$SITE"
test -f "$REPO_ROOT/deploy/APPLY_HOME_HERO_V31.sh"
test -d "$REPO_ROOT/deploy/runtime/home-hero-v31"

echo "[1/4] Aplicando pacote de hero/carrossel editavel"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/APPLY_HOME_HERO_V31.sh"

echo "[2/4] Reiniciando aplicacao"
sudo -n /usr/local/sbin/belastock-vps-control pm2-restart

echo "[3/4] Verificando health e status"
sudo -n /usr/local/sbin/belastock-vps-control health
sudo -n /usr/local/sbin/belastock-vps-control status

echo "[4/4] Verificando pagina publica"
CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/belastock-home.html -w '%{http_code}' "https://belastock.com.br/?hero-v31=$(date +%s)" || true)"
echo "PUBLIC_HOME_HTTP=$CODE"
test "$CODE" = "200"
grep -q "hero-slider" /tmp/belastock-home.html || { echo "[ERRO] hero-slider nao encontrado no HTML publico" >&2; exit 1; }

echo "BELA_STOCK_HOME_HERO_V31=100%_OK"
