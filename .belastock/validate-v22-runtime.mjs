import { pathToFileURL } from 'node:url';

const site = '/home/lojabelastock/htdocs/belastock.com.br';
const { db } = await import(pathToFileURL(`${site}/src/db.mjs`).href);
const { listPaymentProviders } = await import(pathToFileURL(`${site}/src/commerce/payment/registry.mjs`).href);
const { listShippingProviders } = await import(pathToFileURL(`${site}/src/commerce/shipping/registry.mjs`).href);

const requiredTables = [
  'tenants','tenant_domains','tenant_users','tenant_product_listings',
  'payment_gateways','shipping_carriers','product_shipping_rules',
  'customers','customer_addresses','payment_transactions','shipments',
  'customer_sessions','tenant_subscriptions','tenant_user_sessions'
];

const [tableRows] = await db.query('SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()');
const have = new Set(tableRows.map(r => r.TABLE_NAME ?? r.table_name));
const missing = requiredTables.filter(t => !have.has(t));
console.log(`REQUIRED_TABLES=${requiredTables.length}`);
console.log(`MISSING_TABLES=${missing.join(',')}`);
if (missing.length) process.exitCode = 2;

const [tenantRows] = await db.execute('SELECT id,code,name,status,plan_code FROM tenants WHERE id=? LIMIT 1',[1]);
const [domainRows] = await db.execute('SELECT tenant_id,domain,is_primary,status,ssl_status FROM tenant_domains WHERE domain=? LIMIT 1',['belastock.com.br']);
console.log(`ROOT_TENANT=${JSON.stringify(tenantRows[0] ?? null)}`);
console.log(`ROOT_DOMAIN=${JSON.stringify(domainRows[0] ?? null)}`);
if (!tenantRows[0] || tenantRows[0].code !== 'belastock' || tenantRows[0].status !== 'active') process.exitCode = 3;
if (!domainRows[0] || Number(domainRows[0].tenant_id) !== 1 || Number(domainRows[0].is_primary) !== 1 || domainRows[0].status !== 'active') process.exitCode = 4;

const payments = listPaymentProviders();
const shipping = listShippingProviders();
const requiredPayments = ['mercadopago','pagbank','pagarme','stripe','manual_pix'];
const requiredShipping = ['correios','melhor_envio','frenet','jadlog','custom','supplier','pickup'];
console.log(`PAYMENT_PROVIDERS=${payments.map(x=>x.provider).join(',')}`);
console.log(`SHIPPING_PROVIDERS=${shipping.map(x=>x.provider).join(',')}`);
if (requiredPayments.some(x => !payments.some(p => p.provider === x))) process.exitCode = 5;
if (requiredShipping.some(x => !shipping.some(p => p.provider === x))) process.exitCode = 6;

await db.end();
if (process.exitCode) process.exit(process.exitCode);
console.log('V22_RUNTIME_SCHEMA_AND_REGISTRIES=100%_OK');
