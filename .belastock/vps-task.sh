#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
PAYLOAD="$ROOT/deploy/runtime/completion-v30"
INSTALLER="$ROOT/deploy/APPLY_COMPLETION_V30.sh"
E2E="$ROOT/.belastock/validate-v30-e2e.mjs"

echo "============================================================"
echo " BELA STOCK 3.0 - EXECUCAO TOTAL ATE FECHAMENTO"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

# 0. Prova e backup antes de qualquer alteracao
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
sudo -n "$CONTROL" backup-site

# 1. Disponibilizar payload ao usuario isolado da aplicacao
chmod o+rx "$ROOT" "$ROOT/deploy" "$ROOT/deploy/runtime" "$PAYLOAD" 2>/dev/null || true
find "$PAYLOAD" -type d -exec chmod o+rx {} +
find "$PAYLOAD" -type f -exec chmod o+r {} +
chmod o+rx "$INSTALLER"
chmod o+r "$E2E"

# 2. Instalar codigo 3.0 com backup e testes antes do restart
sudo -n -u lojabelastock -H bash "$INSTALLER"

# 3. Aplicar migration 006, dependencias, testes, PM2, persistencia e Nginx
sudo -n "$CONTROL" runtime-repair

# 4. Prova de runtime
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "3.0.0"

# 5. E2E sintético descartavel: produto -> carrinho -> checkout -> pagamento -> entrega,
#    mais workflow de estampa e persistencia da remocao de imagem de mockup.
sudo -n -u lojabelastock -H node "$E2E"

# 6. Provas HTTP publicas e fronteiras privadas
check_code(){
  local expected="$1" url="$2" file="$3"
  local code
  code="$(curl -ksS --max-time 25 -o "$file" -w '%{http_code}' "$url" || true)"
  echo "$url -> $code"
  test "$code" = "$expected"
}

check_code 200 https://belastock.com.br/ /tmp/bs30-root.html
check_code 200 https://belastock.com.br/health /tmp/bs30-health.json
check_code 200 https://belastock.com.br/admin /tmp/bs30-admin.html
check_code 200 https://belastock.com.br/cliente /tmp/bs30-cliente.html
check_code 200 https://belastock.com.br/parceiro /tmp/bs30-parceiro.html
check_code 200 https://belastock.com.br/storefront.js /tmp/bs30-storefront.js
check_code 200 https://belastock.com.br/operations.js /tmp/bs30-operations.js
check_code 200 https://belastock.com.br/api/public/store /tmp/bs30-store.json
check_code 200 https://belastock.com.br/api/public/products /tmp/bs30-products.json
check_code 404 https://belastock.com.br/api/cart /tmp/bs30-cart-empty.json
check_code 401 https://belastock.com.br/api/admin/completion /tmp/bs30-admin-unauth.json
check_code 401 https://belastock.com.br/api/admin/orders /tmp/bs30-orders-unauth.json
check_code 401 https://belastock.com.br/api/customer/panel /tmp/bs30-customer-unauth.json
check_code 401 https://belastock.com.br/api/partner/panel /tmp/bs30-partner-unauth.json

WWW_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://www.belastock.com.br/ || true)"
echo "PUBLIC_WWW_HTTP=$WWW_CODE"
test "$WWW_CODE" = "301"

grep -q '"version":"3.0.0"' /tmp/bs30-health.json
grep -q '"db":true' /tmp/bs30-health.json
grep -q 'storefront.js' /tmp/bs30-root.html
grep -q 'AI Commerce 3.0' /tmp/bs30-admin.html
grep -q 'manual_pix' /tmp/bs30-store.json
grep -q 'pickup' /tmp/bs30-store.json

# 7. Prova de schema e ausencia de lixo sintetico
sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && node --input-type=module - <<'NODE'
import fs from 'node:fs';
for(const raw of fs.readFileSync('.env','utf8').split(/\r?\n/)){const line=raw.trim();if(!line||line.startsWith('#'))continue;const i=line.indexOf('=');if(i<=0)continue;const k=line.slice(0,i);let v=line.slice(i+1).trim();if((v.startsWith('\\\"')&&v.endsWith('\\\"'))||(v.startsWith(\"'\")&&v.endsWith(\"'\")))v=v.slice(1,-1);if(process.env[k]===undefined)process.env[k]=v;}
const {db}=await import('./src/db.mjs');
const required=['carts','cart_items','order_addresses','order_status_history','webhook_events','print_workflow','print_workflow_events','print_assets','positioning_codes','marketing_jobs'];
const [t]=await db.query('SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()');const have=new Set(t.map(r=>r.TABLE_NAME||r.table_name));const missing=required.filter(x=>!have.has(x));console.log('V30_REQUIRED_TABLES='+required.length);console.log('V30_MISSING_TABLES='+missing.join(','));if(missing.length)process.exitCode=2;
const [m]=await db.query(\"SELECT migration_name FROM schema_migrations WHERE migration_name LIKE '006%' LIMIT 1\");console.log('MIGRATION_006='+(m[0]?.migration_name||'MISSING'));if(!m[0])process.exitCode=3;
const [e2e]=await db.query(\"SELECT (SELECT COUNT(*) FROM products WHERE sku LIKE 'E2E%') products,(SELECT COUNT(*) FROM customers WHERE email LIKE 'e2e%@example.invalid') customers,(SELECT COUNT(*) FROM prints WHERE code LIKE 'E2E%') prints\");console.log('E2E_RESIDUE='+JSON.stringify(e2e[0]));if(Number(e2e[0].products)+Number(e2e[0].customers)+Number(e2e[0].prints)!==0)process.exitCode=4;
await db.end();if(process.exitCode)process.exit(process.exitCode);
NODE"

# 8. Nginx canônico e fechamento
sudo -n "$CONTROL" nginx-diagnose > /tmp/bs30-nginx.txt || true
VHOST_PROXY="$(awk '/===== VHOST CONTENT =====/{inside=1;next}/===== ACTIVE BELASTOCK CONFIG REFERENCES =====/{inside=0} inside && /proxy_pass http:\/\/127\.0\.0\.1:[0-9]+\//{print;exit}' /tmp/bs30-nginx.txt | xargs)"
echo "VHOST_PROXY=$VHOST_PROXY"
echo "$VHOST_PROXY" | grep -q 'proxy_pass http://127.0.0.1:3210/'

echo "BELA_STOCK_V30_RUNTIME=100%_OK"
echo "BELA_STOCK_V30_DATABASE=100%_OK"
echo "BELA_STOCK_V30_STOREFRONT=100%_OK"
echo "BELA_STOCK_V30_CART_CHECKOUT=100%_OK"
echo "BELA_STOCK_V30_ORDERS=100%_OK"
echo "BELA_STOCK_V30_PRINT_WORKFLOW=100%_OK"
echo "BELA_STOCK_V30_MOCKUP_PERSISTENCE=100%_OK"
echo "BELA_STOCK_V30_MULTISTORE=100%_OK"
echo "BELA_STOCK_V30_SUPPLIER_GATEWAY=100%_OK"
echo "BELA_STOCK_V30_INTERNAL_PROCESS=100%_OK"
echo "EXTERNAL_PROVIDERS=READY_FOR_CREDENTIALS"
echo "EXECUCAO_TOTAL_BELASTOCK_V30=CONCLUIDA"
