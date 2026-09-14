#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK - ROLLBACK DE ALTERACOES NAO AUTORIZADAS"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/4] Restaurando estado imediatamente anterior"
sudo -n -u "$APP_USER" -H bash "$REPO_ROOT/deploy/ROLLBACK_UNAUTHORIZED_V33.sh"

echo "[2/4] Reiniciando runtime"
sudo -n /usr/local/sbin/belastock-vps-control pm2-restart

echo "[3/4] Validando subdominio loja"
LOJA_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-loja-rollback.html -w '%{http_code}' "https://loja.belastock.com.br/?rollback=$(date +%s)" || true)"
HEALTH_CODE="$(curl -kLsS --max-redirs 5 --max-time 30 -o /tmp/bs-health-rollback.json -w '%{http_code}' "https://loja.belastock.com.br/health?rollback=$(date +%s)" || true)"
echo "LOJA_PUBLIC_HTTP=$LOJA_CODE"
echo "LOJA_HEALTH_HTTP=$HEALTH_CODE"
test "$LOJA_CODE" = 200
test "$HEALTH_CODE" = 200
if grep -q 'Um mega portal' /tmp/bs-loja-rollback.html; then echo '[ERRO] Conteúdo não autorizado ainda publicado' >&2; exit 1; fi
if grep -q '>Eletrônicos<' /tmp/bs-loja-rollback.html; then echo '[ERRO] Eletrônicos ainda publicado no subdomínio' >&2; exit 1; fi
grep -q 'VISTA SUA MELHOR' /tmp/bs-loja-rollback.html

echo "[4/4] Estado final"
sudo -n /usr/local/sbin/belastock-vps-control status

echo "UNAUTHORIZED_V33=ROLLED_BACK"
echo "ELETRONICOS_NO_SUBDOMINIO=REMOVIDO"
echo "LOJA_RESTORED_TO_PREVIOUS_STATE=OK"
