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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.resolve(__dirname, '../public');
const app = Fastify({ logger:true, trustProxy:true, bodyLimit:10 * 1024 * 1024 });

app.addHook('onSend', async (_req, reply, payload) => {
  reply.header('x-content-type-options', 'nosniff');
  reply.header('x-frame-options', 'DENY');
  reply.header('referrer-policy', 'strict-origin-when-cross-origin');
  reply.header('permissions-policy', 'camera=(), microphone=(), geolocation=()');
  return payload;
});

async function requireAdmin(request, reply) {
  const token = request.headers.authorization?.replace(/^Bearer\s+/i, '') || request.headers['x-admin-token'];
  if (!safeEqual(token, config.adminToken)) return reply.code(401).send({ error:'unauthorized' });
}

app.get('/health', async () => ({ ok:true, app:'Bela Stock AI Commerce', version:'2.1.0', db:await pingDb(), time:new Date().toISOString() }));
app.get('/api/public/products', async request => {
  const limit = Math.min(Number(request.query?.limit || 24), 100);
  const [rows] = await db.execute(`SELECT id,sku,name,slug,short_description,price,compare_at_price,status FROM products WHERE status='published' ORDER BY id DESC LIMIT ?`, [limit]);
  return { items:rows };
});
app.get('/api/public/home', async () => {
  const [rows] = await db.query(`SELECT setting_key,setting_value_json FROM settings WHERE setting_key LIKE 'home.%'`);
  return Object.fromEntries(rows.map(r => [r.setting_key.slice(5), JSON.parse(r.setting_value_json)]));
});

app.get('/api/admin/dashboard', { preHandler:requireAdmin }, async () => ({ signals:await aiOrchestrator.signals(), aiMode:aiOrchestrator.mode }));
app.get('/api/admin/supplier-adapters', { preHandler:requireAdmin }, async () => ({ items:listAdapterTypes() }));
app.get('/api/admin/suppliers', { preHandler:requireAdmin }, async () => ({ items:await listSuppliers() }));
app.post('/api/admin/suppliers', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await createSupplier(request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.post('/api/admin/suppliers/:id/test', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await testSupplier(Number(request.params.id)); } catch (error) { return reply.code(502).send({ error:error.message }); }
});
app.post('/api/admin/suppliers/:id/simulate', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await simulateSupplier(Number(request.params.id), request.body || {}); } catch (error) { return reply.code(502).send({ error:error.message }); }
});
app.post('/api/admin/suppliers/:id/sync', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await syncSupplier(Number(request.params.id)); } catch (error) { return reply.code(502).send({ error:error.message }); }
});
app.get('/api/admin/suppliers/:id/items', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await listStagedSupplierItems(Number(request.params.id), request.query || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.post('/api/admin/suppliers/:id/import', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await importSupplierItems(Number(request.params.id), request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.get('/api/admin/suppliers/:id/profile', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await getSupplierProfile(Number(request.params.id)); } catch (error) { return reply.code(400).send({ error:error.message }); }
});
app.put('/api/admin/suppliers/:id/profile', { preHandler:requireAdmin }, async (request, reply) => {
  try { return await updateSupplierProfile(Number(request.params.id), request.body || {}); } catch (error) { return reply.code(400).send({ error:error.message }); }
});

app.post('/api/admin/ai/run', { preHandler:requireAdmin }, async () => aiOrchestrator.runCycle());
app.get('/api/admin/ai/actions', { preHandler:requireAdmin }, async () => {
  const [rows] = await db.query(`SELECT id,action_type,entity_type,entity_id,risk_level,autonomy_mode,reason,status,created_at,finished_at,error_text FROM ai_actions ORDER BY id DESC LIMIT 100`);
  return { items:rows };
});
app.post('/api/admin/ai/actions/:id/approve', { preHandler:requireAdmin }, async request => {
  await db.execute(`UPDATE ai_actions SET status='approved',approved_at=NOW(),approved_by='admin' WHERE id=? AND status='pending_approval'`, [Number(request.params.id)]);
  return { ok:true };
});

app.get('/', async (_request, reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir, 'index.html'), 'utf8')));
app.get('/admin', async (_request, reply) => reply.type('text/html; charset=utf-8').send(await fs.readFile(path.join(publicDir, 'admin.html'), 'utf8')));
app.get('/app.js', async (_request, reply) => reply.type('application/javascript').send(await fs.readFile(path.join(publicDir, 'app.js'), 'utf8')));
app.get('/styles.css', async (_request, reply) => reply.type('text/css').send(await fs.readFile(path.join(publicDir, 'styles.css'), 'utf8')));
app.setNotFoundHandler((request, reply) => reply.code(404).send({ error:'not_found', path:request.url }));

await app.listen({ host:config.host, port:config.port });
app.log.info(`Bela Stock listening on ${config.host}:${config.port}`);
const interval = setInterval(() => aiOrchestrator.runCycle().catch(error => app.log.error(error)), Math.max(60, config.ai.cycleIntervalSeconds) * 1000);
interval.unref();
