#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
PAYLOAD="$ROOT/deploy/runtime/commerce-platform-v22"

echo "============================================================"
echo " BELA STOCK 2.2 - MULTISTORE / PAGAMENTOS / FRETE / PAINEIS"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

# 0. Controle e backup antes da mudanca
CONTROL_OK=0
for attempt in {1..12}; do
  sudo -n "$CONTROL" refresh-control
  if grep -q 'BELASTOCK_NGINX_REPAIR_V2' "$CONTROL"; then CONTROL_OK=1; break; fi
  sleep 10
done
test "$CONTROL_OK" = "1"
sudo -n "$CONTROL" backup-site
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health

# 1. Tornar o payload legivel ao usuario da aplicacao sem abrir escrita publica
chmod o+rx "$ROOT" "$ROOT/deploy" "$ROOT/deploy/runtime" "$PAYLOAD" 2>/dev/null || true
find "$PAYLOAD" -type d -exec chmod o+rx {} +
find "$PAYLOAD" -type f -exec chmod o+r {} +
chmod o+rx "$ROOT/deploy/APPLY_COMMERCE_PLATFORM_V22.sh"

# 2. Aplicar codigo 2.2 com backup por arquivo e testes antes de runtime
sudo -n -u lojabelastock -H bash "$ROOT/deploy/APPLY_COMMERCE_PLATFORM_V22.sh"

# 3. Migrations idempotentes, dependencias, testes, PM2 e persistencia
sudo -n "$CONTROL" runtime-repair

# 4. Provas de banco e runtime
sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health

echo "===== DB SCHEMA PROOF ====="
sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && node --input-type=module - <<'NODE'
import { db } from './src/db.mjs';
const required=['tenants','tenant_domains','tenant_users','tenant_product_listings','payment_gateways','shipping_carriers','product_shipping_rules','customers','customer_addresses','payment_transactions','shipments','customer_sessions','tenant_subscriptions','tenant_user_sessions'];
const [rows]=await db.query('SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()');
const have=new Set(rows.map(r=>r.TABLE_NAME||r.table_name));
const missing=required.filter(x=>!have.has(x));
console.log('REQUIRED_TABLES='+required.length);
console.log('MISSING_TABLES='+missing.join(','));
if(missing.length) process.exit(2);
const [tenant]=await db.query("SELECT id,code,name,status,plan_code FROM tenants WHERE id=1 LIMIT 1");
const [domain]=await db.query("SELECT tenant_id,domain,is_primary,status,ssl_status FROM tenant_domains WHERE domain='belastock.com.br' LIMIT 1");
console.log('ROOT_TENANT='+JSON.stringify(tenant[0]||null));
console.log('ROOT_DOMAIN='+JSON.stringify(domain[0]||null));
await db.end();
NODE"

# 5. Provas publicas e de isolamento de autenticacao
check_code(){
  local expected="$1" url="$2" file="$3"
  local code
  code="$(curl -ksS --max-time 20 -o "$file" -w '%{http_code}' "$url" || true)"
  echo "$url -> $code"
  test "$code" = "$expected"
}

check_code 200 https://belastock.com.br/ /tmp/bs22-root.html
check_code 200 https://belastock.com.br/health /tmp/bs22-health.json
check_code 200 https://belastock.com.br/cliente /tmp/bs22-cliente.html
check_code 200 https://belastock.com.br/parceiro /tmp/bs22-parceiro.html
check_code 200 https://belastock.com.br/admin /tmp/bs22-admin.html
check_code 200 https://belastock.com.br/api/public/store /tmp/bs22-store.json
check_code 401 https://belastock.com.br/api/customer/panel /tmp/bs22-customer-unauth.json
check_code 401 https://belastock.com.br/api/partner/panel /tmp/bs22-partner-unauth.json
check_code 401 https://belastock.com.br/api/admin/payment-providers /tmp/bs22-payment-unauth.json
check_code 401 https://belastock.com.br/api/admin/shipping-providers /tmp/bs22-shipping-unauth.json

WWW_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://www.belastock.com.br/ || true)"
echo "PUBLIC_WWW_HTTP=$WWW_CODE"
test "$WWW_CODE" = "301"

grep -q '"version":"2.2.0"' /tmp/bs22-health.json
grep -q 'Painel do Cliente' /tmp/bs22-cliente.html
grep -q 'Painel do Parceiro' /tmp/bs22-parceiro.html
grep -q 'belastock' /tmp/bs22-store.json

# 6. Prova dos catalogos de gateways e transportadoras sem usar credenciais reais
sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && node --input-type=module - <<'NODE'
import { listPaymentProviders } from './src/commerce/payment/registry.mjs';
import { listShippingProviders } from './src/commerce/shipping/registry.mjs';
const p=listPaymentProviders(); const s=listShippingProviders();
console.log('PAYMENT_PROVIDERS='+p.map(x=>x.provider).join(','));
console.log('SHIPPING_PROVIDERS='+s.map(x=>x.provider).join(','));
for (const x of ['mercadopago','pagbank','pagarme','stripe','manual_pix']) if(!p.some(y=>y.provider===x)) process.exit(3);
for (const x of ['correios','melhor_envio','frenet','jadlog','custom','supplier','pickup']) if(!s.some(y=>y.provider===x)) process.exit(4);
NODE"

# 7. Integridade de upstream e processo
VHOST_PROXY="$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+/' /etc/nginx/sites-enabled/belastock.com.br.conf | head -1)"
echo "VHOST_PROXY=$VHOST_PROXY"
echo "$VHOST_PROXY" | grep -q '127.0.0.1:3210/'
PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "2.2.0"

cat /tmp/bs22-health.json
cat /tmp/bs22-store.json

echo "BELA_STOCK_22_MULTISTORE=100%_OK"
echo "BELA_STOCK_22_CUSTOMER_PANEL=100%_OK"
echo "BELA_STOCK_22_PARTNER_PANEL=100%_OK"
echo "BELA_STOCK_22_PAYMENTS_ARCHITECTURE=100%_OK"
echo "BELA_STOCK_22_SHIPPING_ARCHITECTURE=100%_OK"
echo "EXECUCAO_TOTAL_BELASTOCK_22=CONCLUIDA"
