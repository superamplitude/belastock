#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
PAYLOAD="$(cd "$(dirname "$0")" && pwd)/runtime/supplier-gateway"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/supplier-gateway-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -d "$PAYLOAD" ] || fail "Payload ausente: $PAYLOAD"
mkdir -p "$BACKUP"

FILES=(
  "src/services/supplier-preview.mjs"
  "src/suppliers/registry.mjs"
  "src/services/supplier-gateway-service.mjs"
  "src/services/supplier-service.mjs"
  "src/services/catalog-service.mjs"
  "src/server.mjs"
  "migrations/002_supplier_gateway.sql"
  "tests/supplier-preview.test.mjs"
  "public/admin.html"
  "public/app.js"
  "docs/SUPPLIER-GATEWAY.md"
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

node - "$SITE/package.json" <<'NODE'
const fs=require('fs');
const path=process.argv[2];
const p=JSON.parse(fs.readFileSync(path,'utf8'));
p.version='2.1.0';
p.description='Bela Stock AI Commerce - Node.js, MySQL, AI orchestration and universal supplier gateway';
p.scripts=p.scripts||{};
p.scripts.check='node --check src/server.mjs && node --check src/ai/orchestrator.mjs && node --check src/suppliers/woocommerce.mjs && node --check src/suppliers/registry.mjs && node --check src/services/supplier-preview.mjs && node --check src/services/supplier-gateway-service.mjs && node --check src/services/supplier-service.mjs && node --check src/services/catalog-service.mjs && node --test';
fs.writeFileSync(path,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"
echo "[1/3] Verificando sintaxe e testes"
npm run check

echo "[2/3] Confirmando arquivos instalados"
for rel in "${FILES[@]}"; do test -f "$SITE/$rel"; done

echo "[3/3] Fechamento"
echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"
echo "BACKUP=$BACKUP"
echo "SUPPLIER_GATEWAY_CODE=INSTALLED"
ok "Supplier Gateway 2.1 instalado no codigo; banco/runtime serao validados pelo controlador da VPS."
