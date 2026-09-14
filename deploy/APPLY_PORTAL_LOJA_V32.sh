#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
PAYLOAD="$(cd "$(dirname "$0")" && pwd)/runtime/portal-loja-v32"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/portal-loja-v32-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -f "$SITE/src/server.mjs" ] || fail "Servidor Node ausente."
[ -f "$PAYLOAD/public/portal.html" ] || fail "portal.html ausente no payload."
mkdir -p "$BACKUP/public"
cp -a "$SITE/src/server.mjs" "$BACKUP/server.mjs.before"
cp -a "$SITE/package.json" "$BACKUP/package.json.before"
[ -f "$SITE/public/portal.html" ] && cp -a "$SITE/public/portal.html" "$BACKUP/public/portal.html.before" || true
install -m 0644 "$PAYLOAD/public/portal.html" "$SITE/public/portal.html"

node - "$SITE/src/server.mjs" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
let s=fs.readFileSync(file,'utf8');
const old="app.get('/', { preHandler:requireTenant }, async (_request,reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,'index.html'),'utf8')));";
const next=`app.get('/', { preHandler:requireTenant }, async (request,reply) => {\n  const host=hostOf(request).toLowerCase().split(':')[0];\n  const page=(host==='belastock.com.br'||host==='www1.belastock.com.br')?'portal.html':'index.html';\n  return reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,page),'utf8'));\n});`;
if(s.includes(old)) s=s.replace(old,next);
else if(!s.includes("const page=(host==='belastock.com.br'")) throw new Error('root route anchor not found');
if(s.includes("if (request.url === '/health') return;")) s=s.replace("if (request.url === '/health') return;","if (request.url.startsWith('/health')) return;");
else if(!s.includes("request.url.startsWith('/health')")) throw new Error('health preHandler anchor not found');
s=s.replace(/version:'3\.1\.0'/g,"version:'3.2.0'");
fs.writeFileSync(file,s);
NODE

node - "$SITE/package.json" <<'NODE'
const fs=require('fs');const file=process.argv[2];const p=JSON.parse(fs.readFileSync(file,'utf8'));p.version='3.2.0';p.description='Bela Stock AI Commerce - portal multicanal no dominio raiz e loja Node dedicada no subdominio loja';fs.writeFileSync(file,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"
echo "[1/5] Sintaxe e testes"
node --check src/server.mjs
npm run check

echo "[2/5] Ativando dominio loja no tenant raiz sem remover o dominio principal"
node --input-type=module <<'NODE'
import 'dotenv/config';import mysql from 'mysql2/promise';
const c=await mysql.createConnection({host:process.env.DB_HOST||'127.0.0.1',port:Number(process.env.DB_PORT||3306),user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME});
try{
  const [before]=await c.execute("SELECT id,tenant_id,domain,is_primary,status,ssl_status FROM tenant_domains WHERE domain='loja.belastock.com.br' LIMIT 1");
  console.log('LOJA_DOMAIN_BEFORE='+JSON.stringify(before[0]||null));
  await c.execute(`INSERT INTO tenant_domains (tenant_id,domain,is_primary,status,ssl_status,verified_at) VALUES (1,'loja.belastock.com.br',0,'active','active',NOW()) ON DUPLICATE KEY UPDATE tenant_id=VALUES(tenant_id),is_primary=0,status='active',ssl_status='active',verified_at=NOW()`);
  const [after]=await c.execute("SELECT id,tenant_id,domain,is_primary,status,ssl_status FROM tenant_domains WHERE domain='loja.belastock.com.br' LIMIT 1");
  if(!after[0]||after[0].tenant_id!==1||after[0].status!=='active')throw new Error('loja domain activation failed');
  console.log('LOJA_DOMAIN_AFTER='+JSON.stringify(after[0]));
}finally{await c.end();}
NODE

echo "[3/5] Integridade do portal"
test -s public/portal.html
grep -q 'Um mega portal' public/portal.html
grep -q 'Departamentos Bela Stock' public/portal.html
grep -q 'loja.belastock.com.br' public/portal.html
grep -q "portal.html':'index.html" src/server.mjs
grep -q "request.url.startsWith('/health')" src/server.mjs

echo "[4/5] Versao"
echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"

echo "[5/5] Backup"
echo "BACKUP=$BACKUP"
ok "Código do split Portal/Loja 3.2 instalado com backup, testes e dominio secundario ativo."
