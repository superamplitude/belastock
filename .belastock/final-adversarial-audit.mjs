import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const site='/home/lojabelastock/htdocs/belastock.com.br';
const envText=await fs.readFile(`${site}/.env`,'utf8');
const env={};
for(const raw of envText.split(/\r?\n/)){
  const line=raw.trim();
  if(!line||line.startsWith('#')) continue;
  const i=line.indexOf('=');
  if(i<=0) continue;
  const key=line.slice(0,i).trim();
  let value=line.slice(i+1).trim();
  if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'"))) value=value.slice(1,-1);
  env[key]=value;
  if(process.env[key]===undefined) process.env[key]=value;
}

const {db}=await import(pathToFileURL(`${site}/src/db.mjs`).href+`?audit=${Date.now()}`);
let failures=0;
const fail=(name,detail='')=>{failures++;console.log(`AUDIT_FAIL ${name}${detail?` :: ${detail}`:''}`)};
const ok=(name,detail='')=>console.log(`AUDIT_OK ${name}${detail?` :: ${detail}`:''}`);
const scalar=async(sql,params=[])=>{const [r]=await db.execute(sql,params);return Number(Object.values(r[0]||{})[0]||0)};

try{
  const requiredTables=[
    'schema_migrations','settings','audit_logs','ai_actions','conversations','messages',
    'tenants','tenant_domains','tenant_users','tenant_user_sessions','tenant_product_listings','tenant_subscriptions',
    'customers','customer_addresses','customer_sessions','products','product_variants','prints','mockup_templates','product_mockup_rules',
    'suppliers','supplier_items','supplier_import_profiles','supplier_offers','supplier_orders','supplier_sync_runs',
    'payment_gateways','payment_transactions','shipping_carriers','shipments','product_shipping_rules',
    'carts','cart_items','orders','order_items','order_addresses','order_status_history','webhook_events',
    'print_workflow','print_workflow_events','print_assets','positioning_codes','marketing_jobs'
  ];
  const [tableRows]=await db.query('SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()');
  const have=new Set(tableRows.map(r=>r.TABLE_NAME??r.table_name));
  const missing=requiredTables.filter(t=>!have.has(t));
  if(missing.length) fail('required_tables',missing.join(',')); else ok('required_tables',`${requiredTables.length}/${requiredTables.length}`);

  const migrations=await scalar('SELECT COUNT(*) c FROM schema_migrations');
  if(migrations<6) fail('schema_migrations',String(migrations)); else ok('schema_migrations',String(migrations));

  const [tenantRows]=await db.execute(`SELECT t.id,t.code,t.status,t.plan_code,d.domain,d.is_primary,d.status domain_status,d.ssl_status
    FROM tenants t LEFT JOIN tenant_domains d ON d.tenant_id=t.id AND d.domain='belastock.com.br'
    WHERE t.id=1 LIMIT 1`);
  const root=tenantRows[0];
  if(!root||root.code!=='belastock'||root.status!=='active'||root.domain!=='belastock.com.br'||Number(root.is_primary)!==1||root.domain_status!=='active') fail('root_tenant',JSON.stringify(root||null));
  else ok('root_tenant',`code=${root.code} status=${root.status} domain=${root.domain} ssl=${root.ssl_status}`);

  const orphanChecks=[
    ['order_items_without_order',`SELECT COUNT(*) c FROM order_items x LEFT JOIN orders p ON p.id=x.order_id WHERE p.id IS NULL`],
    ['order_items_without_product',`SELECT COUNT(*) c FROM order_items x LEFT JOIN products p ON p.id=x.product_id WHERE p.id IS NULL`],
    ['cart_items_without_cart',`SELECT COUNT(*) c FROM cart_items x LEFT JOIN carts p ON p.id=x.cart_id WHERE p.id IS NULL`],
    ['cart_items_without_product',`SELECT COUNT(*) c FROM cart_items x LEFT JOIN products p ON p.id=x.product_id WHERE p.id IS NULL`],
    ['listings_without_tenant',`SELECT COUNT(*) c FROM tenant_product_listings x LEFT JOIN tenants p ON p.id=x.tenant_id WHERE p.id IS NULL`],
    ['listings_without_product',`SELECT COUNT(*) c FROM tenant_product_listings x LEFT JOIN products p ON p.id=x.product_id WHERE p.id IS NULL`],
    ['addresses_without_customer',`SELECT COUNT(*) c FROM customer_addresses x LEFT JOIN customers p ON p.id=x.customer_id WHERE p.id IS NULL`],
    ['customer_sessions_without_customer',`SELECT COUNT(*) c FROM customer_sessions x LEFT JOIN customers p ON p.id=x.customer_id WHERE p.id IS NULL`],
    ['partner_sessions_without_user',`SELECT COUNT(*) c FROM tenant_user_sessions x LEFT JOIN tenant_users p ON p.id=x.tenant_user_id WHERE p.id IS NULL`],
    ['payments_without_order',`SELECT COUNT(*) c FROM payment_transactions x LEFT JOIN orders p ON p.id=x.order_id WHERE p.id IS NULL`],
    ['shipments_without_order',`SELECT COUNT(*) c FROM shipments x LEFT JOIN orders p ON p.id=x.order_id WHERE p.id IS NULL`],
    ['print_workflow_without_print',`SELECT COUNT(*) c FROM print_workflow x LEFT JOIN prints p ON p.id=x.print_id WHERE p.id IS NULL`],
    ['print_assets_without_print',`SELECT COUNT(*) c FROM print_assets x LEFT JOIN prints p ON p.id=x.print_id WHERE p.id IS NULL`]
  ];
  for(const [name,sql] of orphanChecks){const n=await scalar(sql);if(n)fail(name,String(n));else ok(name,'0');}

  const duplicateChecks=[
    ['duplicate_product_sku',`SELECT COUNT(*) c FROM (SELECT sku FROM products WHERE sku IS NOT NULL GROUP BY sku HAVING COUNT(*)>1) q`],
    ['duplicate_variant_sku',`SELECT COUNT(*) c FROM (SELECT sku FROM product_variants WHERE sku IS NOT NULL GROUP BY sku HAVING COUNT(*)>1) q`],
    ['duplicate_order_number',`SELECT COUNT(*) c FROM (SELECT order_number FROM orders GROUP BY order_number HAVING COUNT(*)>1) q`],
    ['duplicate_positioning_code',`SELECT COUNT(*) c FROM (SELECT code FROM positioning_codes GROUP BY code HAVING COUNT(*)>1) q`],
    ['duplicate_tenant_domain',`SELECT COUNT(*) c FROM (SELECT domain FROM tenant_domains GROUP BY domain HAVING COUNT(*)>1) q`],
    ['duplicate_customer_email_per_tenant',`SELECT COUNT(*) c FROM (SELECT tenant_id,email FROM customers GROUP BY tenant_id,email HAVING COUNT(*)>1) q`]
  ];
  for(const [name,sql] of duplicateChecks){const n=await scalar(sql);if(n)fail(name,String(n));else ok(name,'0');}

  const semanticChecks=[
    ['enabled_listing_with_unpublished_product',`SELECT COUNT(*) c FROM tenant_product_listings l JOIN products p ON p.id=l.product_id WHERE l.enabled=1 AND p.status<>'published'`],
    ['published_product_without_active_variant',`SELECT COUNT(*) c FROM products p WHERE p.status='published' AND NOT EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id=p.id AND v.status='active')`],
    ['paid_like_order_without_paid_transaction',`SELECT COUNT(*) c FROM orders o WHERE o.status IN ('paid','processing','partially_fulfilled','fulfilled') AND NOT EXISTS (SELECT 1 FROM payment_transactions pt WHERE pt.order_id=o.id AND pt.status='paid')`],
    ['published_print_without_workflow',`SELECT COUNT(*) c FROM prints p WHERE p.status='published' AND NOT EXISTS (SELECT 1 FROM print_workflow w WHERE w.print_id=p.id AND w.stage='published')`],
    ['e2e_product_residue',`SELECT COUNT(*) c FROM products WHERE sku LIKE 'E2E%'`],
    ['e2e_customer_residue',`SELECT COUNT(*) c FROM customers WHERE email LIKE 'e2e%@example.invalid'`],
    ['e2e_print_residue',`SELECT COUNT(*) c FROM prints WHERE code LIKE 'E2E%'`]
  ];
  for(const [name,sql] of semanticChecks){const n=await scalar(sql);if(n)fail(name,String(n));else ok(name,'0');}

  const [counts]=await db.query(`SELECT
    (SELECT COUNT(*) FROM products) products,
    (SELECT COUNT(*) FROM products WHERE status='published') published_products,
    (SELECT COUNT(*) FROM suppliers WHERE status='active') active_suppliers,
    (SELECT COUNT(*) FROM payment_gateways WHERE tenant_id=1 AND enabled=1) enabled_gateways,
    (SELECT COUNT(*) FROM shipping_carriers WHERE tenant_id=1 AND enabled=1) enabled_carriers,
    (SELECT COUNT(*) FROM orders) orders,
    (SELECT COUNT(*) FROM customers) customers`);
  console.log('BUSINESS_READINESS='+JSON.stringify(counts[0]));

  const weakExternalGateways=await scalar(`SELECT COUNT(*) c FROM payment_gateways WHERE tenant_id=1 AND enabled=1 AND provider<>'manual_pix' AND (credentials_encrypted IS NULL OR LENGTH(credentials_encrypted)<20)`);
  if(weakExternalGateways) fail('enabled_external_gateway_without_credentials',String(weakExternalGateways)); else ok('enabled_external_gateway_credentials','no invalid enabled external gateway');

  const adminToken=env.ADMIN_TOKEN||'';
  if(adminToken.length<32) fail('admin_token_strength',`length=${adminToken.length}`); else ok('admin_token_strength',`length=${adminToken.length}`);

  const secretCandidates=['CREDENTIALS_ENCRYPTION_KEY','ENCRYPTION_KEY','APP_KEY'];
  const activeSecret=secretCandidates.find(k=>(env[k]||'').length>=32);
  if(!activeSecret) fail('encryption_secret','no >=32-char encryption key found'); else ok('encryption_secret',activeSecret);

  console.log(`FINAL_DB_ADVERSARIAL_FAILURES=${failures}`);
  if(failures) process.exitCode=20;
} finally {
  await db.end();
}
