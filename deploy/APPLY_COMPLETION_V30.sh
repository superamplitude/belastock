#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
PAYLOAD="$(cd "$(dirname "$0")" && pwd)/runtime/completion-v30"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/completion-v30-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -d "$PAYLOAD" ] || fail "Payload ausente: $PAYLOAD"
[ -f "$SITE/src/server.mjs" ] || fail "Servidor Node ausente."
[ -f "$SITE/package.json" ] || fail "package.json ausente."
mkdir -p "$BACKUP"

FILES=(
  "src/commerce/core-math.mjs"
  "src/commerce/catalog-admin-service.mjs"
  "src/commerce/print-workflow-service.mjs"
  "src/commerce/order-service.mjs"
  "src/commerce/completion-routes.mjs"
  "migrations/006_end_to_end_completion.sql"
  "tests/completion.test.mjs"
  "public/index.html"
  "public/admin.html"
  "public/storefront.js"
  "public/operations.js"
  "public/styles.css"
  "docs/COMPLETION-30.md"
)

cp -a "$SITE/src/server.mjs" "$BACKUP/server.mjs.before"
cp -a "$SITE/package.json" "$BACKUP/package.json.before"

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

node - "$SITE/src/server.mjs" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
let s=fs.readFileSync(file,'utf8');
const importLine="import { registerCompletionRoutes } from './commerce/completion-routes.mjs';";
if(!s.includes(importLine)){
  const anchor="import { customerFromSession, customerPanel, loginCustomer, logoutCustomer, registerCustomer, saveCustomerAddress } from './commerce/customer-service.mjs';";
  if(!s.includes(anchor)) throw new Error('server import anchor not found');
  s=s.replace(anchor,anchor+'\n'+importLine);
}
const call="registerCompletionRoutes(app,{ requireAdmin,requireTenant,requireCustomer,requirePartner,requirePartnerAdmin });";
if(!s.includes(call)){
  const anchor="app.get('/health', async () =>";
  if(!s.includes(anchor)) throw new Error('health anchor not found');
  s=s.replace(anchor,call+'\n\n'+anchor);
}
s=s.replace("version:'2.2.0'","version:'3.0.0'");
s=s.replace("version:'2.1.0'","version:'3.0.0'");
fs.writeFileSync(file,s);
NODE

node - "$SITE/package.json" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
const p=JSON.parse(fs.readFileSync(file,'utf8'));
p.version='3.0.0';
p.description='Bela Stock AI Commerce - end-to-end multistore commerce, supplier routing, print workflow and operations';
p.scripts=p.scripts||{};
const checks=[
  'node --check src/commerce/core-math.mjs',
  'node --check src/commerce/catalog-admin-service.mjs',
  'node --check src/commerce/print-workflow-service.mjs',
  'node --check src/commerce/order-service.mjs',
  'node --check src/commerce/completion-routes.mjs'
];
let base=String(p.scripts.check||'node --test');
for(const c of checks) if(!base.includes(c)) base=c+' && '+base;
p.scripts.check=base;
fs.writeFileSync(file,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"
echo "[1/4] Sintaxe"
node --check src/server.mjs
for f in src/commerce/core-math.mjs src/commerce/catalog-admin-service.mjs src/commerce/print-workflow-service.mjs src/commerce/order-service.mjs src/commerce/completion-routes.mjs public/storefront.js public/operations.js; do node --check "$f"; done

echo "[2/4] Testes"
npm run check

echo "[3/4] Estrutura"
for rel in "${FILES[@]}"; do test -f "$SITE/$rel"; done
grep -q "registerCompletionRoutes" "$SITE/src/server.mjs"
grep -q "version:'3.0.0'" "$SITE/src/server.mjs"
grep -q 'Biblioteca' "$SITE/public/admin.html"
grep -q '/storefront.js' "$SITE/public/index.html"

echo "[4/4] Fechamento"
echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"
echo "BACKUP=$BACKUP"
echo "COMPLETION_V30_CODE=INSTALLED"
ok "Código 3.0 instalado e testado; migrations/runtime serão aplicados pelo controlador da VPS."
