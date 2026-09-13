import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const site='/home/lojabelastock/htdocs/belastock.com.br';
const envText=await fs.readFile(`${site}/.env`,'utf8');
for(const raw of envText.split(/\r?\n/)){
  const line=raw.trim(); if(!line||line.startsWith('#')) continue;
  const i=line.indexOf('='); if(i<=0) continue;
  const key=line.slice(0,i).trim(); let value=line.slice(i+1).trim();
  if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'"))) value=value.slice(1,-1);
  if(process.env[key]===undefined) process.env[key]=value;
}
const {db}=await import(pathToFileURL(`${site}/src/db.mjs`).href);

const [tables]=await db.query(`SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() ORDER BY table_name`);
console.log('TABLES='+tables.map(r=>r.TABLE_NAME??r.table_name).join(','));
const keyTables=['products','product_variants','prints','mockup_templates','product_mockup_rules','orders','order_items','settings','conversations','messages','suppliers','supplier_items','supplier_import_profiles','supplier_offers','supplier_orders','supplier_sync_runs','tenants','tenant_product_listings','customers','customer_addresses','payment_gateways','shipping_carriers','payment_transactions','shipments','ai_actions','audit_logs'];
for(const t of keyTables){
  const [exists]=await db.execute(`SELECT COUNT(*) c FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=?`,[t]);
  if(!Number(exists[0].c)){ console.log(`TABLE_${t}=ABSENT`); continue; }
  const [cols]=await db.execute(`SELECT column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=? ORDER BY ordinal_position`,[t]);
  let count='?'; try{ const [c]=await db.query(`SELECT COUNT(*) c FROM \`${t}\``); count=String(c[0].c); }catch{}
  console.log(`TABLE_${t}_COUNT=${count}`);
  console.log(`TABLE_${t}_COLS=`+cols.map(c=>c.COLUMN_NAME??c.column_name).join(','));
}

const server=await fs.readFile(`${site}/src/server.mjs`,'utf8');
const routes=[...server.matchAll(/app\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]/g)].map(m=>`${m[1].toUpperCase()} ${m[2]}`);
console.log('ROUTES='+routes.join('|'));
const publicFiles=await fs.readdir(`${site}/public`);
console.log('PUBLIC_FILES='+publicFiles.sort().join(','));
const packageJson=JSON.parse(await fs.readFile(`${site}/package.json`,'utf8'));
console.log('VERSION='+packageJson.version);
console.log('SCRIPTS='+Object.keys(packageJson.scripts||{}).join(','));
await db.end();
