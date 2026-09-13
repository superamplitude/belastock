#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"

echo "============================================================"
echo " BELA STOCK - INSPECAO HERO/HOME SEM ALTERAR PRODUCAO"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

test -d "$SITE"
cd "$SITE"

echo "--- PACKAGE ---"
node -e "const p=require('./package.json'); console.log(JSON.stringify({name:p.name,version:p.version,scripts:p.scripts},null,2))" || true

echo "--- PUBLIC FILES ---"
find public -maxdepth 2 -type f -printf '%p\n' | sort

echo "--- HASHES ---"
for f in public/index.html public/admin.html public/storefront.js public/app.js public/operations.js public/styles.css src/server.mjs src/commerce/completion-routes.mjs; do
  if [ -f "$f" ]; then sha256sum "$f"; fi
done

echo "--- INDEX HERO ---"
if [ -f public/index.html ]; then sed -n '1,180p' public/index.html; fi

echo "--- STOREFRONT HOME REFERENCES ---"
if [ -f public/storefront.js ]; then grep -nE 'public/home|hero|topbar' public/storefront.js || true; fi

echo "--- ADMIN HOME REFERENCES ---"
if [ -f public/admin.html ]; then grep -nEi 'home|hero|banner|capa' public/admin.html || true; fi
if [ -f public/app.js ]; then grep -nEi 'home|hero|banner|capa|settings' public/app.js || true; fi
if [ -f public/operations.js ]; then grep -nEi 'home|hero|banner|capa|settings' public/operations.js || true; fi

echo "--- SERVER HOME/SETTINGS REFERENCES ---"
grep -RniE "api/public/home|setting_key|settings_json|home\." src 2>/dev/null | head -n 200 || true

echo "--- DATABASE SETTINGS SCHEMA + HOME DATA ---"
node --input-type=module <<'NODE'
import 'dotenv/config';
import mysql from 'mysql2/promise';
const pool=mysql.createPool({
  host:process.env.DB_HOST||'127.0.0.1',
  port:Number(process.env.DB_PORT||3306),
  user:process.env.DB_USER,
  password:process.env.DB_PASSWORD,
  database:process.env.DB_NAME,
  connectionLimit:1
});
try {
  const [schema]=await pool.query('SHOW CREATE TABLE settings');
  console.log(schema);
  const [rows]=await pool.query("SELECT setting_key,setting_value_json FROM settings WHERE setting_key LIKE 'home.%' ORDER BY setting_key");
  console.log('HOME_SETTINGS=',JSON.stringify(rows,null,2));
  const [tenant]=await pool.query('SELECT id,code,name,settings_json,brand_json FROM tenants WHERE id=1');
  console.log('TENANT_1=',JSON.stringify(tenant,null,2));
} finally { await pool.end(); }
NODE

echo "BELA_STOCK_HERO_INSPECTION=100%_OK"
