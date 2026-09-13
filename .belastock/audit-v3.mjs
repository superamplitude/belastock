import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const site='/home/lojabelastock/htdocs/belastock.com.br';
const envText=await fs.readFile(`${site}/.env`,'utf8');
for(const raw of envText.split(/\r?\n/)){const line=raw.trim();if(!line||line.startsWith('#'))continue;const i=line.indexOf('=');if(i<=0)continue;const key=line.slice(0,i).trim();let value=line.slice(i+1).trim();if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'")))value=value.slice(1,-1);if(process.env[key]===undefined)process.env[key]=value;}
const {db}=await import(pathToFileURL(`${site}/src/db.mjs`).href);
const targets=[['prints','status'],['products','status'],['product_variants','status'],['orders','status'],['suppliers','status'],['supplier_orders','status'],['tenants','status']];
for(const [table,column] of targets){const [rows]=await db.execute(`SELECT column_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=? AND column_name=?`,[table,column]);console.log(`${table}.${column}=${JSON.stringify(rows[0]||null)}`);}
await db.end();
