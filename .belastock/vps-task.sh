#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"

echo "============================================================"
echo " BELA STOCK - AUDITORIA ROOT x LOJA"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"

echo "[1/5] Vhosts relevantes"
for f in /etc/nginx/sites-enabled/belastock.com.br.conf /etc/nginx/sites-enabled/loja.belastock.com.br.conf; do
  echo "--- $f"
  if [ -f "$f" ]; then sudo -n grep -nE 'server_name|proxy_pass|root |listen |ssl_certificate' "$f" || true; else echo MISSING; fi
done

echo "[2/5] Respostas publicas"
for u in https://belastock.com.br/ https://loja.belastock.com.br/; do
  code="$(curl -kLsS --max-redirs 5 --max-time 20 -o /tmp/bs-page.html -w '%{http_code}' "$u?route-audit=$(date +%s)" || true)"
  echo "$u HTTP=$code TITLE=$(grep -oPm1 '(?<=<title>)[^<]+' /tmp/bs-page.html || true) HERO=$(grep -c 'hero-slider' /tmp/bs-page.html || true)"
done

echo "[3/5] Tenant domains"
sudo -n -u "$APP_USER" -H bash -lc "cd '$SITE' && node --input-type=module <<'NODE'
import 'dotenv/config';import mysql from 'mysql2/promise';
const c=await mysql.createConnection({host:process.env.DB_HOST||'127.0.0.1',port:Number(process.env.DB_PORT||3306),user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME});
const [r]=await c.query('SELECT td.id,td.tenant_id,td.domain,td.is_primary,td.status,td.ssl_status FROM tenant_domains td ORDER BY td.tenant_id,td.id');
console.log(JSON.stringify(r));await c.end();
NODE"

echo "[4/5] Rotas HTML live"
sudo -n -u "$APP_USER" -H grep -nE "app.get\('/'|index.html|portal.html" "$SITE/src/server.mjs" || true

echo "[5/5] Status"
sudo -n /usr/local/sbin/belastock-vps-control health
sudo -n /usr/local/sbin/belastock-vps-control status

echo "ROOT_LOJA_AUDIT=COMPLETE"
