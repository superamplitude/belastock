#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/security-hardening-v30-$STAMP"
SERVER="$SITE/src/server.mjs"
PACKAGE="$SITE/package.json"
LOCK="$SITE/package-lock.json"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }
[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -f "$SERVER" ] || fail "Servidor ausente: $SERVER"
[ -f "$PACKAGE" ] || fail "package.json ausente."
mkdir -p "$BACKUP"
cp -a "$SERVER" "$BACKUP/server.mjs.before"
cp -a "$PACKAGE" "$BACKUP/package.json.before"
[ -f "$LOCK" ] && cp -a "$LOCK" "$BACKUP/package-lock.json.before"
echo "SECURITY_BACKUP=$BACKUP"

rollback(){
  echo "[ROLLBACK] Restaurando arquivos anteriores ao hardening"
  cp -a "$BACKUP/server.mjs.before" "$SERVER"
  cp -a "$BACKUP/package.json.before" "$PACKAGE"
  if [ -f "$BACKUP/package-lock.json.before" ]; then cp -a "$BACKUP/package-lock.json.before" "$LOCK"; else rm -f "$LOCK"; fi
  cd "$SITE"
  npm install --omit=dev >/dev/null 2>&1 || true
}
trap 'code=$?; if [ "$code" -ne 0 ]; then rollback; fi; exit "$code"' EXIT

cd "$SITE"
echo "[1/5] Instalando dependencia oficial compatível com Fastify 5"
npm install --save-exact @fastify/rate-limit@11.2.0

echo "[2/5] Aplicando rate limit seletivo a autenticação e cadastro"
node --input-type=module <<'NODE'
import fs from 'node:fs';
const file='src/server.mjs';
let s=fs.readFileSync(file,'utf8');

const importLine="import rateLimit from '@fastify/rate-limit';";
if(!s.includes(importLine)){
  const anchor="import Fastify from 'fastify';";
  if(!s.includes(anchor)) throw new Error('Fastify import anchor not found');
  s=s.replace(anchor,`${anchor}\n${importLine}`);
}

const registration=`await app.register(rateLimit, {\n  global:false,\n  hook:'onRequest',\n  keyGenerator: request => String(request.headers['x-real-ip'] || request.ip || request.raw.socket.remoteAddress || 'unknown').split(',')[0].trim(),\n  continueExceeding:true,\n  errorResponseBuilder: (_request, context) => ({ statusCode:429,error:'Too Many Requests',message:'Limite de tentativas excedido.',retryAfter:context.after })\n});\nconst AUTH_RATE_LIMITS = Object.freeze({\n  customerRegister:{ rateLimit:{ max:5,timeWindow:'10 minutes',groupId:'customer-register' } },\n  customerLogin:{ rateLimit:{ max:8,timeWindow:'1 minute',groupId:'customer-login' } },\n  partnerLogin:{ rateLimit:{ max:8,timeWindow:'1 minute',groupId:'partner-login' } }\n});`;
if(!s.includes('const AUTH_RATE_LIMITS = Object.freeze(')){
  const appAnchor="const app = Fastify({ logger:true, trustProxy:true, bodyLimit:10 * 1024 * 1024 });";
  if(!s.includes(appAnchor)) throw new Error('Fastify app anchor not found');
  s=s.replace(appAnchor,`${appAnchor}\n${registration}`);
}

const replacements=[
  ["app.post('/api/customer/register', { preHandler:requireTenant },", "app.post('/api/customer/register', { preHandler:requireTenant, config:AUTH_RATE_LIMITS.customerRegister },"],
  ["app.post('/api/customer/login', { preHandler:requireTenant },", "app.post('/api/customer/login', { preHandler:requireTenant, config:AUTH_RATE_LIMITS.customerLogin },"],
  ["app.post('/api/partner/login', { preHandler:requireTenant },", "app.post('/api/partner/login', { preHandler:requireTenant, config:AUTH_RATE_LIMITS.partnerLogin },"]
];
for(const [from,to] of replacements){
  if(s.includes(to)) continue;
  if(!s.includes(from)) throw new Error(`route anchor not found: ${from}`);
  s=s.replace(from,to);
}

fs.writeFileSync(file,s);
NODE

echo "[3/5] Verificação estática"
node --check src/server.mjs
node -e "const p=require('./package.json'); if(p.dependencies?.['@fastify/rate-limit']!=='11.2.0') process.exit(2);"
grep -q "import rateLimit from '@fastify/rate-limit'" src/server.mjs
grep -q "AUTH_RATE_LIMITS.customerLogin" src/server.mjs
grep -q "AUTH_RATE_LIMITS.partnerLogin" src/server.mjs
grep -q "AUTH_RATE_LIMITS.customerRegister" src/server.mjs

echo "[4/5] Regressão"
npm run check

echo "[5/5] Integridade do pacote"
npm ls @fastify/rate-limit --depth=0
npm audit --omit=dev --audit-level=high

trap - EXIT
ok "SECURITY_RATE_LIMIT_CODE=INSTALLED"
echo "SECURITY_HARDENING_BACKUP=$BACKUP"
