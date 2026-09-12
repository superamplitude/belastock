import Fastify from 'fastify';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from './config.mjs';
import { pingDb, db } from './db.mjs';
import { safeEqual } from './security/crypto.mjs';
import { createSupplier, listSuppliers, syncSupplier, testSupplier } from './services/supplier-service.mjs';
import { getSupplierProfile, importSupplierItems, listAdapterTypes, listStagedSupplierItems, simulateSupplier, updateSupplierProfile } from './services/supplier-gateway-service.mjs';
import { aiOrchestrator } from './ai/orchestrator.mjs';
import { activateTenantDomain, addTenantDomain, createTenant, getTenant, listTenants, resolveTenantByHost, updateTenant } from './commerce/tenant-service.mjs';
import { createTenantUser, loginTenantUser, logoutTenantUser, tenantUserFromSession } from './commerce/partner-auth-service.mjs';
import { addPlatformProductToTenant, createPartnerProduct, listTenantListings, updateTenantListing } from './commerce/partner-catalog-service.mjs';
import { getProductShippingRule, listPaymentGateways, listShippingCarriers, paymentProviderCatalog, savePaymentGateway, saveProductShippingRule, saveShippingCarrier, shippingProviderCatalog } from './commerce/commerce-config-service.mjs';
import { customerFromSession, customerPanel, loginCustomer, logoutCustomer, registerCustomer, saveCustomerAddress } from './commerce/customer-service.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.resolve(__dirname, '../public');
const app = Fastify({ logger:true, trustProxy:true, bodyLimit:10 * 1024 * 1024 });

const parseCookies = header => Object.fromEntries(String(header || '').split(';').map(v => v.trim()).filter(Boolean).map(part => {
  const i = part.indexOf('=');
  return i < 0 ? [part,''] : [part.slice(0,i), decodeURIComponent(part.slice(i+1))];
}));
const cookie = (name,value,maxAge=2592000) => `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;
const hostOf = request => String(request.headers['x-forwarded-host'] || request.headers.host || '').split(',')[0].trim();

app.addHook('onSend', async (_req, reply, payload) => {
  reply.header('x-content-type-options','nosniff');
  reply.header('x-frame-options','DENY');
  reply.header('referrer-policy','strict-origin-when-cross-origin');
  reply.header('permissions-policy','camera=(), microphone=(), geolocation=()');
  return payload;
});

app.addHook('preHandler', async request => {
  if (request.url === '/health') return;
  const host = hostOf(request);
  let tenant = await resolveTenantByHost(host);
  if (!tenant && /^(127\.0\.0\.1|localhost)(:\d+)?$/i.test(host)) tenant = await getTenant(1);
  request.tenant = tenant;
});

async function requireAdmin(request, reply) {
  const token = request.headers.authorization?.replace(/^Bearer\s+/i,'') || request.headers['x-admin-token'];
  if (!safeEqual(token,config.adminToken)) return reply.code(401).send({ error:'unauthorized' });
}
async function requireTenant(request, reply) {
  if (!request.tenant) return reply.code(404).send({ error:'store_not_found' });
}
async function requireCustomer(request, reply) {
  if (!request.tenant) return reply.code(404).send({ error:'store_not_found' });
  const token = parseCookies(request.headers.cookie).bs_customer_session || request.headers['x-customer-session'];
  const customer = await customerFromSession(request.tenant.id, token);
  if (!customer) return reply.code(401).send({ error:'customer_unauthorized' });
  request.customer = customer;
  request.customerSessionToken = token;
}
async function requirePartner(request, reply) {
  if (!request.tenant) return reply.code(404).send({ error:'store_not_found' });
  const token = parseCookies(request.headers.cookie).bs_partner_session || request.headers['x-partner-session'];
  const user = await tenantUserFromSession(request.tenant.id, token);
  if (!user) return reply.code(401).send({ error:'partner_unauthorized' });
  request.partnerUser = user;
  request.partnerSessionToken = token;
}
async function requirePartnerAdmin(request, reply) {
  const denied = await requirePartner(request, reply);
  if (denied) return denied;
  if (!['owner','admin','finance'].includes(request.partnerUser.role)) return reply.code(403).send({ error:'partner_forbidden' });
}

app.get('/health', async () => ({ ok:true, app:'Bela Stock AI Commerce', version:'2.2.0', db:await pingDb(), time:new Date().toISOString() }));

app.get('/api/public/store', { preHandler:requireTenant }, async request => {
  const tenant = await getTenant(request.tenant.id);
  const [payments,shipping] = await Promise.all([listPaymentGateways(tenant.id),listShippingCarriers(tenant.id)]);
  return {
    id:tenant.id,code:tenant.code,name:tenant.name,currency:tenant.default_currency,
    brand:typeof tenant.brand_json === 'string' ? JSON.parse(tenant.brand_json || '{}') : tenant.brand_json || {},
    domain:tenant.domains.find(d => d.is_primary)?.domain || tenant.domains[0]?.domain || null,
    paymentGateways:payments.filter(x => x.enabled).map(x => ({ id:x.id,provider:x.provider,displayName:x.display_name,sandbox:Boolean(x.sandbox) })),
    shippingCarriers:shipping.filter(x => x.enabled).map(x => ({ id:x.id,provider:x.provider,name:x.name }))
  };
});
app.get('/api/public/products', { preHandler:requireTenant }, async request => {
  const limit = Math.min(Number(request.query?.limit || 24),100);
  const [rows] = await db.execute(`SELECT p.id,p.sku,COALESCE(l.store_name,p.name) name,l.store_slug slug,p.short_description,
      COALESCE(l.price_override,p.price) price,COALESCE(l.compare_at_override,p.compare_at_price) compare_at_price,p.status,l.source_mode
    FROM tenant_product_listings l JOIN products p ON p.id=l.product_id
    WHERE l.tenant_id=? AND l.enabled=1 AND p.status='published'
    ORDER BY l.id DESC LIMIT ?`, [request.tenant.id,limit]);
  return { items:rows };
});
app.get('/api/public/home', { preHandler:requireTenant }, async request => {
  const [rows] = await db.query(`SELECT setting_key,setting_value_json FROM settings WHERE setting_key LIKE 'home.%'`);
  const global = Object.fromEntries(rows.map(r => [r.setting_key.slice(5),JSON.parse(r.setting_value_json)]));
  const tenant = await getTenant(request.tenant.id);
  const settings = typeof tenant.settings_json === 'string' ? JSON.parse(tenant.settings_json || '{}') : tenant.settings_json || {};
  return { ...global,...(settings.home || {}) };
});

app.post('/api/customer/register', { preHandler:requireTenant }, async (request,reply) => {
  try { return await registerCustomer(request.tenant.id,request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.post('/api/customer/login', { preHandler:requireTenant }, async (request,reply) => {
  try {
    const result = await loginCustomer(request.tenant.id,request.body || {},{ ip:request.ip,userAgent:request.headers['user-agent'] });
    reply.header('set-cookie',cookie('bs_customer_session',result.token));
    return { customer:result.customer };
  } catch (error) { return reply.code(401).send({ error:error.message }); }
});
app.post('/api/customer/logout', { preHandler:requireTenant }, async (request,reply) => {
  const token = parseCookies(request.headers.cookie).bs_customer_session || request.headers['x-customer-session'];
  await logoutCustomer(token); reply.header('set-cookie',cookie('bs_customer_session','',0)); return { ok:true };
});
app.get('/api/customer/panel', { preHandler:requireCustomer }, async request => customerPanel(request.tenant.id,request.customer.id));
app.post('/api/customer/addresses', { preHandler:requireCustomer }, async (request,reply) => {
  try { return await saveCustomerAddress(request.tenant.id,request.customer.id,request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});

app.post('/api/partner/login', { preHandler:requireTenant }, async (request,reply) => {
  try {
    const result = await loginTenantUser(request.tenant.id,request.body || {},{ ip:request.ip,userAgent:request.headers['user-agent'] });
    reply.header('set-cookie',cookie('bs_partner_session',result.token));
    return { user:result.user };
  } catch (error) { return reply.code(401).send({ error:error.message }); }
});
app.post('/api/partner/logout', { preHandler:requireTenant }, async (request,reply) => {
  const token = parseCookies(request.headers.cookie).bs_partner_session || request.headers['x-partner-session'];
  await logoutTenantUser(token); reply.header('set-cookie',cookie('bs_partner_session','',0)); return { ok:true };
});
app.get('/api/partner/panel', { preHandler:requirePartner }, async request => {
  const [tenant,listings,payments,shipping,orders] = await Promise.all([
    getTenant(request.tenant.id),listTenantListings(request.tenant.id),listPaymentGateways(request.tenant.id),listShippingCarriers(request.tenant.id),
    db.execute(`SELECT id,order_number,status,grand_total,created_at FROM orders WHERE tenant_id=? ORDER BY id DESC LIMIT 50`, [request.tenant.id])
  ]);
  return { user:request.partnerUser,tenant,listings,payments,shipping,orders:orders[0] };
});
app.get('/api/partner/products', { preHandler:requirePartner }, async request => ({ items:await listTenantListings(request.tenant.id) }));
app.post('/api/partner/products', { preHandler:requirePartner }, async (request,reply) => {
  try { return await createPartnerProduct(request.tenant.id,request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.put('/api/partner/products/:id/listing', { preHandler:requirePartner }, async (request,reply) => {
  try { return await updateTenantListing(request.tenant.id,Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.get('/api/partner/payment-gateways', { preHandler:requirePartnerAdmin }, async request => ({ providers:paymentProviderCatalog(),items:await listPaymentGateways(request.tenant.id) }));
app.post('/api/partner/payment-gateways', { preHandler:requirePartnerAdmin }, async (request,reply) => {
  try { return { items:await savePaymentGateway(request.tenant.id,request.body || {}) }; } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.get('/api/partner/shipping-carriers', { preHandler:requirePartnerAdmin }, async request => ({ providers:shippingProviderCatalog(),items:await listShippingCarriers(request.tenant.id) }));
app.post('/api/partner/shipping-carriers', { preHandler:requirePartnerAdmin }, async (request,reply) => {
  try { return { items:await saveShippingCarrier(request.tenant.id,request.body || {}) }; } catch (error) { return reply.code(400).send({ error:error.message }); }
});

app.get('/api/admin/dashboard', { preHandler:requireAdmin }, async () => ({ signals:await aiOrchestrator.signals(),aiMode:aiOrchestrator.mode }));
app.get('/api/admin/tenants', { preHandler:requireAdmin }, async () => ({ items:await listTenants() }));
app.post('/api/admin/tenants', { preHandler:requireAdmin }, async (request,reply) => { try { return await createTenant(request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.put('/api/admin/tenants/:id', { preHandler:requireAdmin }, async (request,reply) => { try { return await updateTenant(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/tenants/:id/domains', { preHandler:requireAdmin }, async (request,reply) => { try { return await addTenantDomain(Number(request.params.id),request.body?.domain,Boolean(request.body?.primary)); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/tenants/:id/domains/activate', { preHandler:requireAdmin }, async (request,reply) => { try { return await activateTenantDomain(Number(request.params.id),request.body?.domain,Boolean(request.body?.sslActive)); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/tenants/:id/users', { preHandler:requireAdmin }, async (request,reply) => { try { return await createTenantUser(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/tenants/:id/products/:productId', { preHandler:requireAdmin }, async (request,reply) => { try { return await addPlatformProductToTenant(Number(request.params.id),Number(request.params.productId),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.get('/api/admin/payment-providers', { preHandler:requireAdmin }, async () => ({ items:paymentProviderCatalog() }));
app.get('/api/admin/shipping-providers', { preHandler:requireAdmin }, async () => ({ items:shippingProviderCatalog() }));
app.get('/api/admin/products/:id/shipping', { preHandler:requireAdmin }, async request => getProductShippingRule(Number(request.params.id)));
app.put('/api/admin/products/:id/shipping', { preHandler:requireAdmin }, async (request,reply) => { try { return await saveProductShippingRule(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });

app.get('/api/admin/supplier-adapters', { preHandler:requireAdmin }, async () => ({ items:listAdapterTypes() }));
app.get('/api/admin/suppliers', { preHandler:requireAdmin }, async () => ({ items:await listSuppliers() }));
app.post('/api/admin/suppliers', { preHandler:requireAdmin }, async (request,reply) => { try { return await createSupplier(request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/suppliers/:id/test', { preHandler:requireAdmin }, async (request,reply) => { try { return await testSupplier(Number(request.params.id)); } catch (error) { return reply.code(502).send({ error:error.message }); } });
app.post('/api/admin/suppliers/:id/simulate', { preHandler:requireAdmin }, async (request,reply) => { try { return await simulateSupplier(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(502).send({ error:error.message }); } });
app.post('/api/admin/suppliers/:id/sync', { preHandler:requireAdmin }, async (request,reply) => { try { return await syncSupplier(Number(request.params.id)); } catch (error) { return reply.code(502).send({ error:error.message }); } });
app.get('/api/admin/suppliers/:id/items', { preHandler:requireAdmin }, async (request,reply) => { try { return await listStagedSupplierItems(Number(request.params.id),request.query || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.post('/api/admin/suppliers/:id/import', { preHandler:requireAdmin }, async (request,reply) => { try { return await importSupplierItems(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.get('/api/admin/suppliers/:id/profile', { preHandler:requireAdmin }, async (request,reply) => { try { return await getSupplierProfile(Number(request.params.id)); } catch (error) { return reply.code(400).send({ error:error.message }); } });
app.put('/api/admin/suppliers/:id/profile', { preHandler:requireAdmin }, async (request,reply) => { try { return await updateSupplierProfile(Number(request.params.id),request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); } });

app.post('/api/admin/ai/run', { preHandler:requireAdmin }, async () => aiOrchestrator.runCycle());
app.get('/api/admin/ai/actions', { preHandler:requireAdmin }, async () => { const [rows] = await db.query(`SELECT id,action_type,entity_type,entity_id,risk_level,autonomy_mode,reason,status,created_at,finished_at,error_text FROM ai_actions ORDER BY id DESC LIMIT 100`); return { items:rows }; });
app.post('/api/admin/ai/actions/:id/approve', { preHandler:requireAdmin }, async request => { await db.execute(`UPDATE ai_actions SET status='approved',approved_at=NOW(),approved_by='admin' WHERE id=? AND status='pending_approval'`, [Number(request.params.id)]); return { ok:true }; });

app.get('/', { preHandler:requireTenant }, async (_request,reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,'index.html'),'utf8')));
app.get('/admin', async (_request,reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,'admin.html'),'utf8')));
app.get('/cliente', { preHandler:requireTenant }, async (_request,reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,'cliente.html'),'utf8')));
app.get('/parceiro', { preHandler:requireTenant }, async (_request,reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir,'parceiro.html'),'utf8')));
app.get('/app.js', async (_request,reply) => reply.type('application/javascript').send(await fs.readFile(path.join(publicDir,'app.js'),'utf8')));
app.get('/customer.js', async (_request,reply) => reply.type('application/javascript').send(await fs.readFile(path.join(publicDir,'customer.js'),'utf8')));
app.get('/partner.js', async (_request,reply) => reply.type('application/javascript').send(await fs.readFile(path.join(publicDir,'partner.js'),'utf8')));
app.get('/styles.css', async (_request,reply) => reply.type('text/css').send(await fs.readFile(path.join(publicDir,'styles.css'),'utf8')));
app.setNotFoundHandler((request,reply) => reply.code(404).send({ error:'not_found',path:request.url }));

await app.listen({ host:config.host,port:config.port });
app.log.info(`Bela Stock listening on ${config.host}:${config.port}`);
const interval = setInterval(() => aiOrchestrator.runCycle().catch(error => app.log.error(error)),Math.max(60,config.ai.cycleIntervalSeconds) * 1000);
interval.unref();
