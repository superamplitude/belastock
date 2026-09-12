import { db } from '../db.mjs';
import { audit } from '../audit.mjs';
import { getSupplier, getSupplierAdapter } from './supplier-service.mjs';
import { buildPreviewItem, normalizeImportProfile } from './supplier-preview.mjs';
import { promoteSupplierItem } from './catalog-service.mjs';
import { recalculateProductPrice } from './pricing-service.mjs';
import { supportedSupplierAdapters } from '../suppliers/registry.mjs';

const DEFAULT_PROFILE = normalizeImportProfile({});
const clamp = (value, fallback, min, max) => {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
};

export function listAdapterTypes() {
  return supportedSupplierAdapters();
}

export async function getSupplierProfile(supplierId) {
  await getSupplier(supplierId);
  const [rows] = await db.execute(`SELECT * FROM supplier_import_profiles WHERE supplier_id=? LIMIT 1`, [supplierId]);
  return rows[0] ? normalizeImportProfile(rows[0]) : { ...DEFAULT_PROFILE };
}

export async function updateSupplierProfile(supplierId, input = {}) {
  await getSupplier(supplierId);
  const current = await getSupplierProfile(supplierId);
  const next = {
    ...current,
    mode: input.mode === 'production' ? 'production' : (input.mode === 'test' ? 'test' : current.mode),
    syncProducts: input.syncProducts == null ? current.syncProducts : Boolean(input.syncProducts),
    syncPrices: input.syncPrices == null ? current.syncPrices : Boolean(input.syncPrices),
    syncStock: input.syncStock == null ? current.syncStock : Boolean(input.syncStock),
    syncImages: input.syncImages == null ? current.syncImages : Boolean(input.syncImages),
    autoStage: input.autoStage == null ? current.autoStage : Boolean(input.autoStage),
    autoPromote: input.autoPromote == null ? current.autoPromote : Boolean(input.autoPromote),
    targetMarginPct: input.targetMarginPct == null ? current.targetMarginPct : Number(input.targetMarginPct),
    fixedOverhead: input.fixedOverhead == null ? current.fixedOverhead : Number(input.fixedOverhead),
    minimumStock: input.minimumStock == null ? current.minimumStock : Number(input.minimumStock),
    extraLeadTimeDays: input.extraLeadTimeDays == null ? current.extraLeadTimeDays : Number(input.extraLeadTimeDays),
    previewLimit: input.previewLimit == null ? current.previewLimit : clamp(input.previewLimit, current.previewLimit, 1, 50),
    rules: input.rules && typeof input.rules === 'object' ? input.rules : current.rules
  };
  if (!(next.targetMarginPct >= 0 && next.targetMarginPct < 95)) throw new Error('targetMarginPct must be between 0 and 95');
  if (!Number.isFinite(next.fixedOverhead) || next.fixedOverhead < 0) throw new Error('fixedOverhead must be >= 0');
  if (!Number.isFinite(next.minimumStock) || next.minimumStock < 0) throw new Error('minimumStock must be >= 0');

  await db.execute(`INSERT INTO supplier_import_profiles
    (supplier_id,mode,sync_products,sync_prices,sync_stock,sync_images,auto_stage,auto_promote,target_margin_pct,fixed_overhead,minimum_stock,extra_lead_time_days,preview_limit,rules_json)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE mode=VALUES(mode),sync_products=VALUES(sync_products),sync_prices=VALUES(sync_prices),sync_stock=VALUES(sync_stock),sync_images=VALUES(sync_images),auto_stage=VALUES(auto_stage),auto_promote=VALUES(auto_promote),target_margin_pct=VALUES(target_margin_pct),fixed_overhead=VALUES(fixed_overhead),minimum_stock=VALUES(minimum_stock),extra_lead_time_days=VALUES(extra_lead_time_days),preview_limit=VALUES(preview_limit),rules_json=VALUES(rules_json),updated_at=NOW()`, [
    supplierId, next.mode, Number(next.syncProducts), Number(next.syncPrices), Number(next.syncStock), Number(next.syncImages), Number(next.autoStage), Number(next.autoPromote), next.targetMarginPct, next.fixedOverhead, next.minimumStock, next.extraLeadTimeDays, next.previewLimit, JSON.stringify(next.rules || {})
  ]);
  await audit({ actorType:'admin', action:'supplier.profile.update', entityType:'supplier', entityId:supplierId, after:next });
  return getSupplierProfile(supplierId);
}

export async function simulateSupplier(supplierId, options = {}) {
  const supplier = await getSupplier(supplierId);
  const profile = await getSupplierProfile(supplierId);
  const limit = clamp(options.limit, profile.previewLimit || 20, 1, 50);
  const adapter = await getSupplierAdapter(supplierId);
  const result = await adapter.listProducts({ page:1, perPage:limit });
  const items = result.items.slice(0, limit).map(raw => buildPreviewItem(adapter.normalizeProduct(raw), profile));
  const summary = {
    requested: limit,
    received: items.length,
    eligible: items.filter(item => item.eligible).length,
    warnings: items.reduce((n, item) => n + item.issues.filter(issue => issue.level === 'warning').length, 0),
    errors: items.reduce((n, item) => n + item.issues.filter(issue => issue.level === 'error').length, 0),
    supplierTotal: result.total,
    sourcePages: result.totalPages
  };
  await audit({ actorType:'admin', action:'supplier.simulate', entityType:'supplier', entityId:supplierId, metadata:{ adapterType:supplier.adapter_type, summary } });
  return { supplier:{ id:supplier.id, name:supplier.name, adapterType:supplier.adapter_type }, profile, summary, items };
}

export async function listStagedSupplierItems(supplierId, options = {}) {
  await getSupplier(supplierId);
  const limit = clamp(options.limit, 50, 1, 200);
  const offset = clamp(options.offset, 0, 0, 1_000_000);
  const q = String(options.q || '').trim();
  const like = `%${q}%`;
  const [rows] = await db.execute(`SELECT si.id,si.external_id,si.parent_external_id,si.external_sku,si.name,si.item_type,si.status,si.normalized_json,si.source_modified_at,si.last_seen_at,
      so.product_variant_id,pv.product_id,p.status AS product_status
    FROM supplier_items si
    LEFT JOIN supplier_offers so ON so.supplier_item_id=si.id
    LEFT JOIN product_variants pv ON pv.id=so.product_variant_id
    LEFT JOIN products p ON p.id=pv.product_id
    WHERE si.supplier_id=? AND (?='' OR si.name LIKE ? OR COALESCE(si.external_sku,'') LIKE ?)
    ORDER BY si.id DESC LIMIT ? OFFSET ?`, [supplierId, q, like, like, limit, offset]);
  return {
    items: rows.map(row => ({
      id: row.id,
      externalId: row.external_id,
      externalSku: row.external_sku,
      name: row.name,
      type: row.item_type,
      sourceStatus: row.status,
      productId: row.product_id || null,
      productVariantId: row.product_variant_id || null,
      productStatus: row.product_status || null,
      normalized: typeof row.normalized_json === 'string' ? JSON.parse(row.normalized_json) : row.normalized_json,
      sourceModifiedAt: row.source_modified_at,
      lastSeenAt: row.last_seen_at
    })), limit, offset, q
  };
}

async function productIdForVariant(productVariantId) {
  if (!productVariantId) return null;
  const [rows] = await db.execute(`SELECT product_id FROM product_variants WHERE id=? LIMIT 1`, [productVariantId]);
  return rows[0]?.product_id || null;
}

export async function importSupplierItems(supplierId, input = {}) {
  await getSupplier(supplierId);
  const profile = await getSupplierProfile(supplierId);
  const requestedIds = Array.isArray(input.itemIds) ? [...new Set(input.itemIds.map(Number).filter(Number.isInteger))].slice(0, 200) : [];
  const limit = clamp(input.limit, 50, 1, 200);
  let rows;
  if (requestedIds.length) {
    const placeholders = requestedIds.map(() => '?').join(',');
    [rows] = await db.execute(`SELECT id,normalized_json FROM supplier_items WHERE supplier_id=? AND id IN (${placeholders}) ORDER BY id ASC`, [supplierId, ...requestedIds]);
  } else {
    [rows] = await db.execute(`SELECT si.id,si.normalized_json FROM supplier_items si LEFT JOIN supplier_offers so ON so.supplier_item_id=si.id WHERE si.supplier_id=? AND so.id IS NULL ORDER BY si.id ASC LIMIT ?`, [supplierId, limit]);
  }

  const results = [];
  for (const row of rows) {
    const normalized = typeof row.normalized_json === 'string' ? JSON.parse(row.normalized_json) : row.normalized_json;
    const preview = buildPreviewItem(normalized, profile);
    if (!preview.eligible) {
      results.push({ itemId:row.id, ok:false, skipped:true, reason:'rules', issues:preview.issues });
      continue;
    }
    try {
      const promoted = await promoteSupplierItem(row.id);
      const productId = promoted.productId || await productIdForVariant(promoted.productVariantId);
      let pricing = null;
      if (productId && profile.syncPrices) {
        pricing = await recalculateProductPrice(productId, { targetMarginPct:profile.targetMarginPct, fixedOverhead:profile.fixedOverhead });
      }
      results.push({ itemId:row.id, ok:true, ...promoted, productId:productId || promoted.productId || null, pricing });
    } catch (error) {
      results.push({ itemId:row.id, ok:false, error:error.message });
    }
  }
  const summary = { requested:rows.length, imported:results.filter(r => r.ok).length, skipped:results.filter(r => r.skipped).length, failed:results.filter(r => !r.ok && !r.skipped).length };
  await audit({ actorType:'admin', action:'supplier.import', entityType:'supplier', entityId:supplierId, metadata:{ summary, itemIds:rows.map(r => r.id) } });
  return { profile, summary, results };
}
