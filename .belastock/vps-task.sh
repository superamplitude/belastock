#!/usr/bin/env bash
set -Eeuo pipefail

CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"

echo "============================================================"
echo " BELA STOCK - EXECUCAO TOTAL / FIX 502 CAUSA-RAIZ"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

CONTROL_OK=0
for attempt in {1..12}; do
  echo "[CONTROL] tentativa $attempt/12"
  sudo -n "$CONTROL" refresh-control
  if grep -q 'BELASTOCK_NGINX_REPAIR_V1' "$CONTROL"; then
    CONTROL_OK=1
    echo "[CONTROL] revisao NGINX-REPAIR confirmada"
    break
  fi
  echo "[CONTROL] CDN ainda entregou revisao anterior; aguardando 20s"
  sleep 20
done
test "$CONTROL_OK" = "1"

# Evidencia previa: app 2.1 + banco precisam estar saudaveis antes de trocar upstream.
sudo -n "$CONTROL" db-test
curl -sS --fail --max-time 10 http://127.0.0.1:3210/health

# Correcao unica, com backup, nginx -t, rollback automatico e validacao publica.
sudo -n "$CONTROL" nginx-repair

echo "===== PROVA FINAL ====="
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health

PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "2.1.0"

ROOT_CODE="$(curl -ksS --max-time 20 -o /tmp/bs-final-root.html -w '%{http_code}' https://belastock.com.br/)"
HEALTH_CODE="$(curl -ksS --max-time 20 -o /tmp/bs-final-health.json -w '%{http_code}' https://belastock.com.br/health)"
WWW_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://www.belastock.com.br/)"

echo "PUBLIC_ROOT_HTTP=$ROOT_CODE"
echo "PUBLIC_HEALTH_HTTP=$HEALTH_CODE"
echo "PUBLIC_WWW_HTTP=$WWW_CODE"
cat /tmp/bs-final-health.json

test "$ROOT_CODE" = "200"
test "$HEALTH_CODE" = "200"
test "$WWW_CODE" = "301"
grep -q '"version":"2.1.0"' /tmp/bs-final-health.json

echo "ORIGIN_BELASTOCK=100%_OK"
echo "PUBLICO_BELASTOCK=100%_OK"
echo "BELA_STOCK_502=ENCERRADO_CAUSA_RAIZ"
echo "EXECUCAO_TOTAL_BELASTOCK=CONCLUIDA"
