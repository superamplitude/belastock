#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
PAYLOAD="$(cd "$(dirname "$0")" && pwd)/runtime/home-hero-v31"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/home-hero-v31-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE" ] || fail "Site ausente: $SITE"
[ -d "$PAYLOAD" ] || fail "Payload ausente: $PAYLOAD"
[ -f "$SITE/src/server.mjs" ] || fail "Servidor Node ausente."
[ -f "$SITE/package.json" ] || fail "package.json ausente."
mkdir -p "$BACKUP"

FILES=(
  "src/commerce/home-customization.mjs"
  "public/index.html"
  "public/admin.html"
  "public/storefront.js"
  "public/home-admin.js"
  "public/styles.css"
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

echo "[assets] Restaurando pacote de quatro banners WEBP"
ASSET_DIR="$SITE/public/assets/hero"
mkdir -p "$ASSET_DIR"
for f in hero-01.webp hero-02.webp hero-03.webp hero-04.webp; do
  if [ -f "$ASSET_DIR/$f" ]; then mkdir -p "$BACKUP/public/assets/hero"; cp -a "$ASSET_DIR/$f" "$BACKUP/public/assets/hero/$f"; fi
done
ASSET_B64="$BACKUP/hero-assets.zip.b64"
ASSET_ZIP="$BACKUP/hero-assets.zip"
cat "$PAYLOAD"/assets-pack/hero-assets.zip.b64.part* > "$ASSET_B64"
base64 -d "$ASSET_B64" > "$ASSET_ZIP"
printf '%s  %s\n' 'e347b786fd9f3dcc12726e52d98b8d96e4859669c504a255cc992330f26e941c' "$ASSET_ZIP" | sha256sum -c -
python3 - "$ASSET_ZIP" "$ASSET_DIR" <<'PYZIP'
import sys,zipfile,pathlib
zp=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2])
allowed={f'hero-{i:02d}.webp' for i in range(1,5)}
with zipfile.ZipFile(zp) as z:
    names=set(z.namelist())
    if names!=allowed: raise SystemExit(f'asset names invalid: {names}')
    for name in sorted(names):
        data=z.read(name)
        if not (len(data)>12 and data[:4]==b'RIFF' and data[8:12]==b'WEBP'):
            raise SystemExit(f'invalid webp: {name}')
        (out/name).write_bytes(data)
PYZIP

node - "$SITE/src/server.mjs" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
let s=fs.readFileSync(file,'utf8');
const importLine="import { registerHomeCustomizationRoutes } from './commerce/home-customization.mjs';";
if(!s.includes(importLine)){
  const anchors=[
    "import { registerCompletionRoutes } from './commerce/completion-routes.mjs';",
    "import { customerFromSession, customerPanel, loginCustomer, logoutCustomer, registerCustomer, saveCustomerAddress } from './commerce/customer-service.mjs';"
  ];
  const anchor=anchors.find(a=>s.includes(a));
  if(!anchor)throw new Error('server import anchor not found');
  s=s.replace(anchor,anchor+'\n'+importLine);
}
const call="registerHomeCustomizationRoutes(app,{ requireAdmin,requireTenant });";
if(!s.includes(call)){
  const anchor="app.get('/health', async () =>";
  if(!s.includes(anchor))throw new Error('health anchor not found');
  s=s.replace(anchor,call+'\n\n'+anchor);
}
s=s.replace("version:'3.0.0'","version:'3.1.0'");
s=s.replace("version:'2.2.0'","version:'3.1.0'");
fs.writeFileSync(file,s);
NODE

node - "$SITE/package.json" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
const p=JSON.parse(fs.readFileSync(file,'utf8'));
p.version='3.1.0';
p.description='Bela Stock AI Commerce - end-to-end commerce with editable storefront hero';
p.scripts=p.scripts||{};
const checks=[
  'node --check src/commerce/home-customization.mjs',
  'node --check public/home-admin.js',
  'node --check public/storefront.js'
];
let base=String(p.scripts.check||'node --test');
for(const c of checks)if(!base.includes(c))base=c+' && '+base;
p.scripts.check=base;
fs.writeFileSync(file,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"

echo "[1/5] Sintaxe"
node --check src/server.mjs
node --check src/commerce/home-customization.mjs
node --check public/storefront.js
node --check public/home-admin.js

echo "[2/5] Seed idempotente das configuracoes de capa"
node --input-type=module <<'NODE'
import 'dotenv/config';
import mysql from 'mysql2/promise';
const pool=mysql.createPool({
  host:process.env.DB_HOST||'127.0.0.1',port:Number(process.env.DB_PORT||3306),
  user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME,connectionLimit:1
});
const defaults={
  'home.hero_cta_label':'Ver coleção',
  'home.hero_cta_href':'#catalogo',
  'home.hero_autoplay_ms':6500,
  'home.hero_slides':[
    {src:'/assets/hero/hero-01.webp',alt:'Modelo Bela Stock com camiseta branca em fundo lilás',active:true,position:'72% center'},
    {src:'/assets/hero/hero-02.webp',alt:'Modelo Bela Stock com camiseta roxa no ambiente da loja',active:true,position:'73% center'},
    {src:'/assets/hero/hero-03.webp',alt:'Modelo Bela Stock com camiseta roxa em destaque',active:true,position:'74% center'},
    {src:'/assets/hero/hero-04.webp',alt:'Modelo Bela Stock com camiseta branca no ambiente da loja',active:true,position:'76% center'}
  ]
};
try{
  for(const [k,v] of Object.entries(defaults)){
    await pool.execute('INSERT INTO settings (setting_key,setting_value_json) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_key=VALUES(setting_key)',[k,JSON.stringify(v)]);
  }
  const [rows]=await pool.query("SELECT setting_key FROM settings WHERE setting_key IN ('home.hero_cta_label','home.hero_cta_href','home.hero_autoplay_ms','home.hero_slides') ORDER BY setting_key");
  if(rows.length!==4)throw new Error(`hero seed incompleto: ${rows.length}/4`);
  console.log('HOME_HERO_SETTINGS=4/4');
}finally{await pool.end();}
NODE

echo "[3/5] Suite completa"
npm run check

echo "[4/5] Integridade do payload"
for rel in "${FILES[@]}"; do test -f "$SITE/$rel"; done
for f in hero-01.webp hero-02.webp hero-03.webp hero-04.webp; do test -s "$SITE/public/assets/hero/$f"; done
grep -q "registerHomeCustomizationRoutes" "$SITE/src/server.mjs"
grep -q "hero-slider" "$SITE/public/index.html"
grep -q "home-hero" "$SITE/public/admin.html"
grep -q "api/admin/home-settings" "$SITE/public/home-admin.js"
grep -q "hero_slides" "$SITE/public/storefront.js"

echo "[5/5] Fechamento"
echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"
echo "BACKUP=$BACKUP"
echo "HOME_HERO_V31_CODE=INSTALLED"
ok "Bela Stock 3.1: capa/carrossel editavel instalada com backup e testes."
