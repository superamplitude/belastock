#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
BACKUP="/home/lojabelastock/backups/loja-visual-rc14-v33-20260914_143013"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -d "$BACKUP" ] || fail "Backup pré-alteração ausente: $BACKUP"
[ -f "$BACKUP/public/index.html.before" ] || fail "index.html pré-alteração ausente"
[ -f "$BACKUP/src/server.mjs.before" ] || fail "server.mjs pré-alteração ausente"
[ -f "$BACKUP/package.json.before" ] || fail "package.json pré-alteração ausente"

install -m 0644 "$BACKUP/public/index.html.before" "$SITE/public/index.html"
install -m 0644 "$BACKUP/src/server.mjs.before" "$SITE/src/server.mjs"
install -m 0644 "$BACKUP/package.json.before" "$SITE/package.json"

cd "$SITE"
node --check src/server.mjs
node --check public/storefront.js

grep -q 'VISTA SUA MELHOR VERSÃO' public/index.html
if grep -q 'Um mega portal' public/index.html; then fail "Conteúdo não autorizado ainda presente"; fi
if grep -q '>Eletrônicos<' public/index.html; then fail "Eletrônicos ainda presente no subdomínio"; fi

VERSION="$(node -p "require('./package.json').version")"
echo "RESTORED_VERSION=$VERSION"
echo "RESTORED_FROM=$BACKUP"
ok "Alterações visuais/conteúdos não autorizados revertidos para o estado imediatamente anterior."
