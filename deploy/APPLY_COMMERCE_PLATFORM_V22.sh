#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
PAYLOAD="$(cd "$(dirname "$0")" && pwd)/runtime/commerce-platform-v22"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/commerce-platform-v22-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -d "$PAYLOAD" ] || fail "Payload ausente: $PAYLOAD"
[ -f "$SITE/src/services/supplier-gateway-service.mjs" ] || fail "Supplier Gateway 2.1 ausente; instale a base antes da 2.2."
mkdir -p "$BACKUP"

FILES=(
  "src/server.mjs"
  "src/commerce/tenant-service.mjs"
  "src/commerce/commerce-config-service.mjs"
  "src/commerce/partner-catalog-service.mjs"
  "src/commerce/customer-service.mjs"
  "src/commerce/partner-auth-service.mjs"
  "src/commerce/payment/registry.mjs"
  "src/commerce/shipping/registry.mjs"
  "migrations/003_multistore_payments_shipping.sql"
  "migrations/004_customer_sessions_partner_subscriptions.sql"
  "migrations/005_partner_user_sessions.sql"
  "tests/commerce-providers.test.mjs"
  "public/admin.html"
  "public/app.js"
  "public/cliente.html"
  "public/customer.js"
  "public/parceiro.html"
  "public/partner.js"
  "docs/MULTISTORE-COMMERCE.md"
)

for rel in "${FILES[@]}"; do
  src="$PAYLOAD/$rel"
  dst="$SITE/$rel"
  [ -f "$src" ] || fail "Payload incompleto: $rel"
  if [ -f "$dst" ]; then
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$dst" "$BACKUP/$rel"
  fi
  mkdir -p "$(dirname "$dst")"
  install -m 0644 "$src" "$dst"
done

cp -a "$SITE/package.json" "$BACKUP/package.json.before"
node - "$SITE/package.json" <<'NODE'
const fs=require('fs');
const path=process.argv[2];
const p=JSON.parse(fs.readFileSync(path,'utf8'));
p.version='2.2.0';
p.description='Bela Stock AI Commerce - multi-store, white-label, supplier gateway, customer and partner panels';
p.scripts=p.scripts||{};
p.scripts.check=[
  'node --check src/server.mjs',
  'node --check src/ai/orchestrator.mjs',
  'node --check src/suppliers/woocommerce.mjs',
  'node --check src/suppliers/registry.mjs',
  'node --check src/services/supplier-preview.mjs',
  'node --check src/services/supplier-gateway-service.mjs',
  'node --check src/services/supplier-service.mjs',
  'node --check src/services/catalog-service.mjs',
  'node --check src/commerce/tenant-service.mjs',
  'node --check src/commerce/commerce-config-service.mjs',
  'node --check src/commerce/partner-catalog-service.mjs',
  'node --check src/commerce/customer-service.mjs',
  'node --check src/commerce/partner-auth-service.mjs',
  'node --check src/commerce/payment/registry.mjs',
  'node --check src/commerce/shipping/registry.mjs',
  'node --test'
].join(' && ');
fs.writeFileSync(path,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"
echo "[1/3] Verificando código e testes"
npm run check

echo "[2/3] Confirmando estrutura"
for rel in "${FILES[@]}"; do test -f "$SITE/$rel"; done
grep -q "version:'2.2.0'" "$SITE/src/server.mjs"
grep -q 'Painel do Cliente' "$SITE/public/cliente.html"
grep -q 'Painel do Parceiro' "$SITE/public/parceiro.html"

echo "[3/3] Fechamento"
echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"
echo "BACKUP=$BACKUP"
echo "MULTISTORE_COMMERCE_CODE=INSTALLED"
ok "Bela Stock 2.2 instalado no código; migrations/runtime serão aplicados pelo controlador da VPS."
