import crypto from 'node:crypto';
import { db } from '../db.mjs';
import { decryptJson, encryptJson } from '../security/crypto.mjs';
import { buildSupplierAdapter, supportedSupplierAdapters } from '../suppliers/registry.mjs';
import { audit } from '../audit.mjs';

const fingerprint = obj => crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex');

function ensureAdapterSupported(type) {
  const adapter = supportedSupplierAdapters().find(item => item.type === type);
  if (!adapter) throw new Error(`Unknown supplier adapter: ${type}`);
  if (!adapter.implemented) throw new Error(`Supplier adapter not implemented yet: ${type}`);
  return adapter;
}

function adapterCredentials(input, adapterType) {
  if (adapterType === 'woocommerce') {
    if (!input.consumerKey || !input.consumerSecret) throw new Error('consumerKey and consumerSecret are required for WooCommerce');
    return { consumerKey: input.consumerKey, consumerSecret: input.consumerSecret, webhookSecret: input.webhookSecret || '' };
  }
  return input.credentials && typeof input.credentials === 'object' ? input.credentials : {};
}

async function persistSupplierItem({ supplierId, normalized, raw }) {
  const externalId = normalized.type === 'variation' ? `${normalized.parentExternalId}:v:${normalized.externalId}` : normalized.externalId;
  const hash = fingerprint(normalized);
  const [existing] = await db.execute(`SELECT id, content_hash FROM supplier_items WHERE supplier_id=? AND external_id=? LIMIT 1`, [supplierId, externalId]);
  await db.execute(
    `INSERT INTO supplier_items
     (supplier_id, external_id, parent_external_id, external_sku, name, item_type, status, normalized_json, raw_json, content_hash, source_modified_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE parent_external_id=VALUES(parent_external_id), external_sku=VALUES(external_sku), name=VALUES(name), item_type=VALUES(item_type), status=VALUES(status), normalized_json=VALUES(normalized_json), raw_json=VALUES(raw_json), content_hash=VALUES(content_hash), source_modified_at=VALUES(source_modified_at), last_seen_at=NOW(), updated_at=NOW()`,
    [supplierId, externalId, normalized.parentExternalId || null, normalized.externalSku, normalized.name, normalized.type, normalized.status,
      JSON.stringify(normalized), JSON.stringify(raw), hash, normalized.modifiedAt ? new Date(normalized.modifiedAt) : null]
  );
  return { changed: !existing[0] || existing[0].content_hash !== hash };
}

export async function createSupplier(input) {
  const adapterType = String(input.adapterType || 'woocommerce').trim().toLowerCase();
  ensureAdapterSupported(adapterType);
  if (!input.name || !input.baseUrl) throw new Error('name and baseUrl are required');
  const encrypted = encryptJson(adapterCredentials(input, adapterType));
  const interval = Math.min(10080, Math.max(5, Number(input.syncIntervalMinutes || 60)));
  const [result] = await db.execute(
    `INSERT INTO suppliers (name, adapter_type, base_url, credentials_encrypted, status, sync_interval_minutes)
     VALUES (?, ?, ?, ?, 'pending', ?)`,
    [input.name.trim(), adapterType, input.baseUrl.trim().replace(/\/+$/, ''), encrypted, interval]
  );
  await audit({ actorType: 'admin', action: 'supplier.create', entityType: 'supplier', entityId: result.insertId,
    after: { name: input.name, baseUrl: input.baseUrl, adapterType } });
  return getSupplier(result.insertId);
}

export async function listSuppliers() {
  const [rows] = await db.query(`SELECT id, name, adapter_type, base_url, status, health_score, sync_interval_minutes, last_sync_at, last_error, created_at, updated_at FROM suppliers ORDER BY id DESC`);
  return rows;
}

export async function getSupplier(id) {
  const [rows] = await db.execute(`SELECT * FROM suppliers WHERE id=? LIMIT 1`, [id]);
  if (!rows[0]) throw new Error('Supplier not found');
  return rows[0];
}

export async function getSupplierAdapter(id) {
  const supplier = await getSupplier(id);
  return buildSupplierAdapter(supplier, decryptJson(supplier.credentials_encrypted));
}

export async function testSupplier(id) {
  const adapter = await getSupplierAdapter(id);
  try {
    const result = await adapter.testConnection();
    await db.execute(`UPDATE suppliers SET status='active', last_error=NULL, health_score=100 WHERE id=?`, [id]);
    await audit({ actorType: 'system', action: 'supplier.connection.ok', entityType: 'supplier', entityId: id, metadata: result });
    return result;
  } catch (error) {
    await db.execute(`UPDATE suppliers SET status='error', last_error=?, health_score=0 WHERE id=?`, [String(error.message).slice(0, 1000), id]);
    await audit({ actorType: 'system', action: 'supplier.connection.error', entityType: 'supplier', entityId: id, metadata: { error: error.message } });
    throw error;
  }
}

export async function syncSupplier(id) {
  const supplier = await getSupplier(id);
  const adapter = buildSupplierAdapter(supplier, decryptJson(supplier.credentials_encrypted));
  let page = 1, imported = 0, variants = 0, changed = 0, totalPages = 1;
  const started = new Date();
  let runId = null;
  try {
    try {
      const [run] = await db.execute(`INSERT INTO supplier_sync_runs (supplier_id,run_type,status) VALUES (?,'sync','running')`, [id]);
      runId = run.insertId;
    } catch {}
    do {
      const result = await adapter.listProducts({ page, perPage: 100 });
      totalPages = result.totalPages;
      for (const raw of result.items) {
        const normalized = adapter.normalizeProduct(raw);
        const saved = await persistSupplierItem({ supplierId: id, normalized, raw });
        imported++;
        if (saved.changed) changed++;
        if (normalized.type === 'variable' && normalized.variationIds.length) {
          let variationPage = 1, variationPages = 1;
          do {
            const vr = await adapter.listVariations(raw.id, { page: variationPage, perPage: 100 });
            variationPages = vr.totalPages;
            for (const rawVariation of vr.items) {
              const normalizedVariation = adapter.normalizeVariation(raw, rawVariation);
              const vs = await persistSupplierItem({ supplierId: id, normalized: normalizedVariation, raw: rawVariation });
              variants++;
              if (vs.changed) changed++;
            }
            variationPage++;
          } while (variationPage <= variationPages);
        }
      }
      page++;
    } while (page <= totalPages);

    const metrics = { imported, variants, changed, pages: totalPages };
    await db.execute(`UPDATE suppliers SET status='active', last_sync_at=NOW(), last_error=NULL, health_score=100 WHERE id=?`, [id]);
    if (runId) await db.execute(`UPDATE supplier_sync_runs SET status='completed',metrics_json=?,finished_at=NOW() WHERE id=?`, [JSON.stringify(metrics), runId]);
    await audit({ actorType: 'ai', action: 'supplier.sync', entityType: 'supplier', entityId: id, metadata: { ...metrics, startedAt: started.toISOString() } });
    return metrics;
  } catch (error) {
    await db.execute(`UPDATE suppliers SET status='error', last_error=?, health_score=GREATEST(0, health_score-20) WHERE id=?`, [String(error.message).slice(0, 1000), id]);
    if (runId) await db.execute(`UPDATE supplier_sync_runs SET status='failed',error_text=?,finished_at=NOW() WHERE id=?`, [String(error.message).slice(0, 2000), runId]);
    throw error;
  }
}
